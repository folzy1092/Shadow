#include "pkcs12_apple.h"

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonCrypto.h>

#include <algorithm>
#include <cstring>

using std::string;
using std::vector;

namespace {

struct Node {
	uint8_t tag = 0;
	size_t start = 0;
	size_t contentStart = 0;
	size_t end = 0;
};

// Definite-length DER/BER only (OpenSSL, Keychain and resellers' tools write DER).
bool ReadNode(const string& buffer, size_t position, size_t limit, Node& node)
{
	if (position + 2 > limit) {
		return false;
	}
	size_t cursor = position;
	node.start = position;
	node.tag = (uint8_t)buffer[cursor++];
	uint8_t first = (uint8_t)buffer[cursor++];
	size_t length = 0;
	if (first < 0x80) {
		length = first;
	} else {
		size_t count = first & 0x7f;
		if (count == 0 || count > 4 || cursor + count > limit) {
			return false;
		}
		for (size_t i = 0; i < count; i++) {
			length = (length << 8) | (uint8_t)buffer[cursor++];
		}
	}
	if (cursor + length > limit) {
		return false;
	}
	node.contentStart = cursor;
	node.end = cursor + length;
	return true;
}

bool Children(const string& buffer, const Node& parent, vector<Node>& out)
{
	out.clear();
	size_t position = parent.contentStart;
	while (position < parent.end) {
		Node child;
		if (!ReadNode(buffer, position, parent.end, child)) {
			return false;
		}
		out.push_back(child);
		position = child.end;
	}
	return true;
}

bool Root(const string& buffer, Node& node)
{
	return ReadNode(buffer, 0, buffer.size(), node);
}

// OCTET STRING content, primitive or constructed (also [0] IMPLICIT forms).
bool Octets(const string& buffer, const Node& node, string& out)
{
	if (node.tag & 0x20) {
		vector<Node> parts;
		if (!Children(buffer, node, parts)) {
			return false;
		}
		for (const Node& part : parts) {
			if (!Octets(buffer, part, out)) {
				return false;
			}
		}
		return true;
	}
	out.append(buffer, node.contentStart, node.end - node.contentStart);
	return true;
}

string Oid(const string& buffer, const Node& node)
{
	if (node.tag != 0x06 || node.end <= node.contentStart) {
		return "";
	}
	uint8_t first = (uint8_t)buffer[node.contentStart];
	string result = std::to_string(first / 40) + "." + std::to_string(first % 40);
	uint64_t value = 0;
	for (size_t i = node.contentStart + 1; i < node.end; i++) {
		uint8_t byte = (uint8_t)buffer[i];
		value = (value << 7) | (byte & 0x7f);
		if (!(byte & 0x80)) {
			result += "." + std::to_string(value);
			value = 0;
		}
	}
	return result;
}

uint64_t Integer(const string& buffer, const Node& node)
{
	uint64_t value = 0;
	for (size_t i = node.contentStart; i < node.end && i < node.contentStart + 8; i++) {
		value = (value << 8) | (uint8_t)buffer[i];
	}
	return value;
}

// MARK: Hashes

struct Hash {
	size_t digestLength;
	size_t blockLength;
	CCHmacAlgorithm hmac;
};

bool HashForDigestOid(const string& oid, Hash& hash)
{
	if (oid == "1.3.14.3.2.26") { hash = { CC_SHA1_DIGEST_LENGTH, 64, kCCHmacAlgSHA1 }; return true; }
	if (oid == "2.16.840.1.101.3.4.2.1") { hash = { CC_SHA256_DIGEST_LENGTH, 64, kCCHmacAlgSHA256 }; return true; }
	if (oid == "2.16.840.1.101.3.4.2.2") { hash = { CC_SHA384_DIGEST_LENGTH, 128, kCCHmacAlgSHA384 }; return true; }
	if (oid == "2.16.840.1.101.3.4.2.3") { hash = { CC_SHA512_DIGEST_LENGTH, 128, kCCHmacAlgSHA512 }; return true; }
	return false;
}

bool HashForPrfOid(const string& oid, Hash& hash)
{
	if (oid == "1.2.840.113549.2.7") { return HashForDigestOid("1.3.14.3.2.26", hash); }
	if (oid == "1.2.840.113549.2.9") { return HashForDigestOid("2.16.840.1.101.3.4.2.1", hash); }
	if (oid == "1.2.840.113549.2.10") { return HashForDigestOid("2.16.840.1.101.3.4.2.2", hash); }
	if (oid == "1.2.840.113549.2.11") { return HashForDigestOid("2.16.840.1.101.3.4.2.3", hash); }
	return false;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
string Digest(const Hash& hash, const string& data)
{
	unsigned char out[CC_SHA512_DIGEST_LENGTH];
	switch (hash.digestLength) {
		case CC_SHA1_DIGEST_LENGTH: CC_SHA1(data.data(), (CC_LONG)data.size(), out); break;
		case CC_SHA256_DIGEST_LENGTH: CC_SHA256(data.data(), (CC_LONG)data.size(), out); break;
		case CC_SHA384_DIGEST_LENGTH: CC_SHA384(data.data(), (CC_LONG)data.size(), out); break;
		default: CC_SHA512(data.data(), (CC_LONG)data.size(), out); break;
	}
	return string((const char*)out, hash.digestLength);
}
#pragma clang diagnostic pop

// RFC 7292 appendix B: id 1 = key, 2 = IV, 3 = MAC key. password is BMPString + 00 00.
string PKCS12KDF(const Hash& hash, const string& password, const string& salt, uint64_t iterations, uint8_t id, size_t length)
{
	const size_t v = hash.blockLength;
	auto fill = [&](const string& value) {
		string result;
		if (value.empty()) {
			return result;
		}
		size_t size = v * ((value.size() + v - 1) / v);
		while (result.size() < size) {
			result += value;
		}
		result.resize(size);
		return result;
	};
	string D(v, (char)id);
	string I = fill(salt) + fill(password);
	string out;
	if (iterations == 0) {
		iterations = 1;
	}
	while (out.size() < length) {
		string A = Digest(hash, D + I);
		for (uint64_t i = 1; i < iterations; i++) {
			A = Digest(hash, A);
		}
		out += A;
		string B;
		while (B.size() < v) {
			B += A;
		}
		B.resize(v);
		// I_j = (I_j + B + 1) mod 2^(8v) for every v-byte block of I.
		for (size_t j = 0; j < I.size(); j += v) {
			unsigned carry = 1;
			for (size_t k = v; k-- > 0;) {
				unsigned sum = (uint8_t)I[j + k] + (uint8_t)B[k] + carry;
				I[j + k] = (char)(sum & 0xff);
				carry = sum >> 8;
			}
		}
	}
	out.resize(length);
	return out;
}

// RFC 8018 PBKDF2 on CCHmac (CCKeyDerivationPBKDF may reject an empty password).
string PBKDF2(const Hash& hash, const string& password, const string& salt, uint64_t iterations, size_t length)
{
	string out;
	if (iterations == 0) {
		iterations = 1;
	}
	for (uint32_t block = 1; out.size() < length; block++) {
		string input = salt;
		input.push_back((char)(block >> 24));
		input.push_back((char)(block >> 16));
		input.push_back((char)(block >> 8));
		input.push_back((char)block);
		unsigned char u[CC_SHA512_DIGEST_LENGTH];
		unsigned char t[CC_SHA512_DIGEST_LENGTH];
		CCHmac(hash.hmac, password.data(), password.size(), input.data(), input.size(), u);
		memcpy(t, u, hash.digestLength);
		for (uint64_t i = 1; i < iterations; i++) {
			CCHmac(hash.hmac, password.data(), password.size(), u, hash.digestLength, u);
			for (size_t k = 0; k < hash.digestLength; k++) {
				t[k] ^= u[k];
			}
		}
		out.append((const char*)t, hash.digestLength);
	}
	out.resize(length);
	return out;
}

bool Decrypt(CCAlgorithm algorithm, const string& key, const string& iv, const string& data, string& out)
{
	out.assign(data.size() + 32, 0);
	size_t moved = 0;
	CCCryptorStatus status = CCCrypt(kCCDecrypt, algorithm, kCCOptionPKCS7Padding,
		key.data(), key.size(), iv.empty() ? NULL : iv.data(),
		data.data(), data.size(), &out[0], out.size(), &moved);
	if (status != kCCSuccess) {
		out.clear();
		return false;
	}
	out.resize(moved);
	return true;
}

// Decrypts with the scheme in `algorithm` (an AlgorithmIdentifier node).
// false = unsupported scheme or the password does not fit.
bool DecryptWithScheme(const string& buffer, const Node& algorithm, const string& data,
                       const string& passwordUTF8, const string& passwordBMP,
                       string& out, string& error)
{
	vector<Node> parts;
	if (!Children(buffer, algorithm, parts) || parts.empty()) {
		error = "повреждённый .p12";
		return false;
	}
	string oid = Oid(buffer, parts[0]);
	if (oid == "1.2.840.113549.1.5.13") { // PBES2
		vector<Node> params, kdf, kdfParams, scheme;
		if (parts.size() < 2 || !Children(buffer, parts[1], params) || params.size() < 2 ||
			!Children(buffer, params[0], kdf) || kdf.size() < 2 || Oid(buffer, kdf[0]) != "1.2.840.113549.1.5.12" ||
			!Children(buffer, kdf[1], kdfParams) || kdfParams.size() < 2 ||
			!Children(buffer, params[1], scheme) || scheme.size() < 2) {
			error = "в .p12 неподдерживаемая схема PBES2";
			return false;
		}
		string salt;
		Octets(buffer, kdfParams[0], salt);
		uint64_t iterations = Integer(buffer, kdfParams[1]);
		size_t keyLength = 0;
		Hash prf;
		HashForDigestOid("1.3.14.3.2.26", prf);
		for (size_t i = 2; i < kdfParams.size(); i++) {
			if (kdfParams[i].tag == 0x02) {
				keyLength = (size_t)Integer(buffer, kdfParams[i]);
			} else if (kdfParams[i].tag == 0x30) {
				vector<Node> prfParts;
				if (!Children(buffer, kdfParams[i], prfParts) || prfParts.empty() || !HashForPrfOid(Oid(buffer, prfParts[0]), prf)) {
					error = "в .p12 неподдерживаемый PRF";
					return false;
				}
			}
		}
		string schemeOid = Oid(buffer, scheme[0]);
		string iv;
		Octets(buffer, scheme[1], iv);
		CCAlgorithm cipher = kCCAlgorithmAES;
		size_t defaultKeyLength = 0;
		if (schemeOid == "2.16.840.1.101.3.4.1.2") { defaultKeyLength = 16; }
		else if (schemeOid == "2.16.840.1.101.3.4.1.22") { defaultKeyLength = 24; }
		else if (schemeOid == "2.16.840.1.101.3.4.1.42") { defaultKeyLength = 32; }
		else if (schemeOid == "1.2.840.113549.3.7") { defaultKeyLength = 24; cipher = kCCAlgorithm3DES; }
		else {
			error = "в .p12 неподдерживаемый шифр " + schemeOid;
			return false;
		}
		if (keyLength == 0) {
			keyLength = defaultKeyLength;
		}
		string key = PBKDF2(prf, passwordUTF8, salt, iterations, keyLength);
		return Decrypt(cipher, key, iv, data, out);
	}

	// PKCS#12 password-based encryption (SHA-1).
	CCAlgorithm cipher;
	size_t keyLength;
	bool twoKey3DES = false;
	if (oid == "1.2.840.113549.1.12.1.3") { cipher = kCCAlgorithm3DES; keyLength = 24; }
	else if (oid == "1.2.840.113549.1.12.1.4") { cipher = kCCAlgorithm3DES; keyLength = 16; twoKey3DES = true; }
	else if (oid == "1.2.840.113549.1.12.1.5") { cipher = kCCAlgorithmRC2; keyLength = 16; }
	else if (oid == "1.2.840.113549.1.12.1.6") { cipher = kCCAlgorithmRC2; keyLength = 5; }
	else {
		error = "в .p12 неподдерживаемое шифрование " + oid;
		return false;
	}
	vector<Node> params;
	if (parts.size() < 2 || !Children(buffer, parts[1], params) || params.size() < 2) {
		error = "повреждённый .p12";
		return false;
	}
	string salt;
	Octets(buffer, params[0], salt);
	uint64_t iterations = Integer(buffer, params[1]);
	Hash sha1;
	HashForDigestOid("1.3.14.3.2.26", sha1);
	string key = PKCS12KDF(sha1, passwordBMP, salt, iterations, 1, keyLength);
	string iv = PKCS12KDF(sha1, passwordBMP, salt, iterations, 2, 8);
	if (twoKey3DES) {
		key += key.substr(0, 8);
	}
	return Decrypt(cipher, key, iv, data, out);
}

void ReadBags(const string& safe, vector<string>& keys, vector<string>& certificates,
              const string& passwordUTF8, const string& passwordBMP, bool& decryptFailed, string& error)
{
	Node root;
	vector<Node> bags;
	if (!Root(safe, root) || !Children(safe, root, bags)) {
		return;
	}
	for (const Node& bag : bags) {
		vector<Node> bagParts, valueParts;
		if (!Children(safe, bag, bagParts) || bagParts.size() < 2 || !Children(safe, bagParts[1], valueParts) || valueParts.empty()) {
			continue;
		}
		string bagId = Oid(safe, bagParts[0]);
		const Node& value = valueParts[0];
		if (bagId == "1.2.840.113549.1.12.10.1.1") { // keyBag
			keys.push_back(safe.substr(value.start, value.end - value.start));
		} else if (bagId == "1.2.840.113549.1.12.10.1.2") { // pkcs8ShroudedKeyBag
			vector<Node> encrypted;
			if (!Children(safe, value, encrypted) || encrypted.size() < 2) {
				continue;
			}
			string data, plain;
			Octets(safe, encrypted[1], data);
			if (DecryptWithScheme(safe, encrypted[0], data, passwordUTF8, passwordBMP, plain, error)) {
				keys.push_back(plain);
			} else {
				decryptFailed = true;
			}
		} else if (bagId == "1.2.840.113549.1.12.10.1.3") { // certBag
			vector<Node> certParts, certValue;
			if (!Children(safe, value, certParts) || certParts.size() < 2 || Oid(safe, certParts[0]) != "1.2.840.113549.1.9.22.1" ||
				!Children(safe, certParts[1], certValue) || certValue.empty()) {
				continue;
			}
			string certificate;
			Octets(safe, certValue[0], certificate);
			certificates.push_back(certificate);
		}
	}
}

} // namespace

bool ShadowParsePKCS12(const string& p12, const string& password, string& privateKeyInfo,
                       vector<string>& certificates, bool& wrongPassword, string& error)
{
	wrongPassword = false;
	certificates.clear();
	privateKeyInfo.clear();

	string passwordBMP;
	@autoreleasepool {
		NSString* text = [[NSString alloc] initWithBytes:password.data() length:password.size() encoding:NSUTF8StringEncoding] ?: @"";
		NSData* utf16 = [text dataUsingEncoding:NSUTF16BigEndianStringEncoding] ?: [NSData data];
		passwordBMP.assign((const char*)utf16.bytes, utf16.length);
	}
	passwordBMP.append(2, '\0');

	Node pfx;
	vector<Node> top, authSafe, explicitContent;
	if (!Root(p12, pfx) || !Children(p12, pfx, top) || top.size() < 2 ||
		!Children(p12, top[1], authSafe) || authSafe.size() < 2 || Oid(p12, authSafe[0]) != "1.2.840.113549.1.7.1" ||
		!Children(p12, authSafe[1], explicitContent) || explicitContent.empty()) {
		error = "Файл не похож на .p12";
		return false;
	}
	string authBytes;
	Octets(p12, explicitContent[0], authBytes);

	bool hasMac = false;
	if (top.size() > 2) {
		vector<Node> mac, digestInfo, digestAlgorithm;
		if (Children(p12, top[2], mac) && mac.size() >= 2 && Children(p12, mac[0], digestInfo) && digestInfo.size() >= 2 &&
			Children(p12, digestInfo[0], digestAlgorithm) && !digestAlgorithm.empty()) {
			Hash hash;
			if (HashForDigestOid(Oid(p12, digestAlgorithm[0]), hash)) {
				hasMac = true;
				string expected, salt;
				Octets(p12, digestInfo[1], expected);
				Octets(p12, mac[1], salt);
				uint64_t iterations = mac.size() > 2 ? Integer(p12, mac[2]) : 1;
				string macKey = PKCS12KDF(hash, passwordBMP, salt, iterations, 3, hash.digestLength);
				unsigned char computed[CC_SHA512_DIGEST_LENGTH];
				CCHmac(hash.hmac, macKey.data(), macKey.size(), authBytes.data(), authBytes.size(), computed);
				if (expected.size() != hash.digestLength || memcmp(expected.data(), computed, hash.digestLength) != 0) {
					wrongPassword = true;
					error = "Неверный пароль от .p12";
					return false;
				}
			}
		}
	}

	Node authRoot;
	vector<Node> contentInfos;
	if (!Root(authBytes, authRoot) || !Children(authBytes, authRoot, contentInfos)) {
		error = "Повреждённое содержимое .p12";
		return false;
	}
	vector<string> keys;
	bool decryptFailed = false;
	for (const Node& info : contentInfos) {
		vector<Node> parts, content;
		if (!Children(authBytes, info, parts) || parts.size() < 2 || !Children(authBytes, parts[1], content) || content.empty()) {
			continue;
		}
		string type = Oid(authBytes, parts[0]);
		string safe;
		if (type == "1.2.840.113549.1.7.1") { // data
			Octets(authBytes, content[0], safe);
		} else if (type == "1.2.840.113549.1.7.6") { // encryptedData
			vector<Node> encryptedData, encryptedContentInfo;
			if (!Children(authBytes, content[0], encryptedData) || encryptedData.size() < 2 ||
				!Children(authBytes, encryptedData[1], encryptedContentInfo) || encryptedContentInfo.size() < 3) {
				continue;
			}
			string data;
			Octets(authBytes, encryptedContentInfo[2], data);
			if (!DecryptWithScheme(authBytes, encryptedContentInfo[1], data, password, passwordBMP, safe, error)) {
				decryptFailed = true;
				continue;
			}
		} else {
			continue;
		}
		ReadBags(safe, keys, certificates, password, passwordBMP, decryptFailed, error);
	}

	if (keys.empty()) {
		if (decryptFailed && !hasMac && error.empty()) {
			wrongPassword = true;
			error = "Неверный пароль от .p12";
		} else if (error.empty()) {
			error = "В .p12 нет закрытого ключа";
		}
		return false;
	}
	privateKeyInfo = keys.front();
	return true;
}

bool ShadowRSAKeyFromPKCS8(const string& privateKeyInfo, string& rsaPrivateKey)
{
	Node root;
	vector<Node> parts, algorithm;
	if (!Root(privateKeyInfo, root) || !Children(privateKeyInfo, root, parts) || parts.size() < 3 ||
		!Children(privateKeyInfo, parts[1], algorithm) || algorithm.empty() ||
		Oid(privateKeyInfo, algorithm[0]) != "1.2.840.113549.1.1.1" || parts[2].tag != 0x04) {
		return false;
	}
	rsaPrivateKey.assign(privateKeyInfo, parts[2].contentStart, parts[2].end - parts[2].contentStart);
	return true;
}
