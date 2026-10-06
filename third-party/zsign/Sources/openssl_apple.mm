// Shadow: replaces zsign's openssl.cpp. Telegram's own OpenSSL is built
// without CMS/RC2/DES and a second OpenSSL would clash with its symbols, so the
// p12 is opened with SecPKCS12Import, the signature is made with SecKey and
// the CMS SignedData is assembled by hand (DER layout checked against
// `openssl cms -verify`). Apple CA certificates below are copied from upstream.
#include "common.h"
#include "base64.h"
#include "openssl.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <CommonCrypto/CommonDigest.h>
#include <time.h>

const char* ZSignAsset::s_szAppleDevCACert = ""
"-----BEGIN CERTIFICATE-----\n"
"MIIEIjCCAwqgAwIBAgIIAd68xDltoBAwDQYJKoZIhvcNAQEFBQAwYjELMAkGA1UE\n"
"BhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xJjAkBgNVBAsTHUFwcGxlIENlcnRp\n"
"ZmljYXRpb24gQXV0aG9yaXR5MRYwFAYDVQQDEw1BcHBsZSBSb290IENBMB4XDTEz\n"
"MDIwNzIxNDg0N1oXDTIzMDIwNzIxNDg0N1owgZYxCzAJBgNVBAYTAlVTMRMwEQYD\n"
"VQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxv\n"
"cGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3Bl\n"
"ciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwggEiMA0GCSqGSIb3\n"
"DQEBAQUAA4IBDwAwggEKAoIBAQDKOFSmy1aqyCQ5SOmM7uxfuH8mkbw0U3rOfGOA\n"
"YXdkXqUHI7Y5/lAtFVZYcC1+xG7BSoU+L/DehBqhV8mvexj/avoVEkkVCBmsqtsq\n"
"Mu2WY2hSFT2Miuy/axiV4AOsAX2XBWfODoWVN2rtCbauZ81RZJ/GXNG8V25nNYB2\n"
"NqSHgW44j9grFU57Jdhav06DwY3Sk9UacbVgnJ0zTlX5ElgMhrgWDcHld0WNUEi6\n"
"Ky3klIXh6MSdxmilsKP8Z35wugJZS3dCkTm59c3hTO/AO0iMpuUhXf1qarunFjVg\n"
"0uat80YpyejDi+l5wGphZxWy8P3laLxiX27Pmd3vG2P+kmWrAgMBAAGjgaYwgaMw\n"
"HQYDVR0OBBYEFIgnFwmpthhgi+zruvZHWcVSVKO3MA8GA1UdEwEB/wQFMAMBAf8w\n"
"HwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wLgYDVR0fBCcwJTAjoCGg\n"
"H4YdaHR0cDovL2NybC5hcHBsZS5jb20vcm9vdC5jcmwwDgYDVR0PAQH/BAQDAgGG\n"
"MBAGCiqGSIb3Y2QGAgEEAgUAMA0GCSqGSIb3DQEBBQUAA4IBAQBPz+9Zviz1smwv\n"
"j+4ThzLoBTWobot9yWkMudkXvHcs1Gfi/ZptOllc34MBvbKuKmFysa/Nw0Uwj6OD\n"
"Dc4dR7Txk4qjdJukw5hyhzs+r0ULklS5MruQGFNrCk4QttkdUGwhgAqJTleMa1s8\n"
"Pab93vcNIx0LSiaHP7qRkkykGRIZbVf1eliHe2iK5IaMSuviSRSqpd1VAKmuu0sw\n"
"ruGgsbwpgOYJd+W+NKIByn/c4grmO7i77LpilfMFY0GCzQ87HUyVpNur+cmV6U/k\n"
"TecmmYHpvPm0KdIBembhLoz2IYrF+Hjhga6/05Cdqa3zr/04GpZnMBxRpVzscYqC\n"
"tGwPDBUf\n"
"-----END CERTIFICATE-----\n";

const char* ZSignAsset::s_szAppleDevCACertG3 = ""
"-----BEGIN CERTIFICATE-----\n"
"MIIEUTCCAzmgAwIBAgIQfK9pCiW3Of57m0R6wXjF7jANBgkqhkiG9w0BAQsFADBi\n"
"MQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBw\n"
"bGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3Qg\n"
"Q0EwHhcNMjAwMjE5MTgxMzQ3WhcNMzAwMjIwMDAwMDAwWjB1MUQwQgYDVQQDDDtB\n"
"cHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9u\n"
"IEF1dGhvcml0eTELMAkGA1UECwwCRzMxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJ\n"
"BgNVBAYTAlVTMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2PWJ/KhZ\n"
"C4fHTJEuLVaQ03gdpDDppUjvC0O/LYT7JF1FG+XrWTYSXFRknmxiLbTGl8rMPPbW\n"
"BpH85QKmHGq0edVny6zpPwcR4YS8Rx1mjjmi6LRJ7TrS4RBgeo6TjMrA2gzAg9Dj\n"
"+ZHWp4zIwXPirkbRYp2SqJBgN31ols2N4Pyb+ni743uvLRfdW/6AWSN1F7gSwe0b\n"
"5TTO/iK1nkmw5VW/j4SiPKi6xYaVFuQAyZ8D0MyzOhZ71gVcnetHrg21LYwOaU1A\n"
"0EtMOwSejSGxrC5DVDDOwYqGlJhL32oNP/77HK6XF8J4CjDgXx9UO0m3JQAaN4LS\n"
"VpelUkl8YDib7wIDAQABo4HvMIHsMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0j\n"
"BBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wRAYIKwYBBQUHAQEEODA2MDQGCCsG\n"
"AQUFBzABhihodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNh\n"
"MC4GA1UdHwQnMCUwI6AhoB+GHWh0dHA6Ly9jcmwuYXBwbGUuY29tL3Jvb3QuY3Js\n"
"MB0GA1UdDgQWBBQJ/sAVkPmvZAqSErkmKGMMl+ynsjAOBgNVHQ8BAf8EBAMCAQYw\n"
"EAYKKoZIhvdjZAYCAQQCBQAwDQYJKoZIhvcNAQELBQADggEBAK1lE+j24IF3RAJH\n"
"Qr5fpTkg6mKp/cWQyXMT1Z6b0KoPjY3L7QHPbChAW8dVJEH4/M/BtSPp3Ozxb8qA\n"
"HXfCxGFJJWevD8o5Ja3T43rMMygNDi6hV0Bz+uZcrgZRKe3jhQxPYdwyFot30ETK\n"
"XXIDMUacrptAGvr04NM++i+MZp+XxFRZ79JI9AeZSWBZGcfdlNHAwWx/eCHvDOs7\n"
"bJmCS1JgOLU5gm3sUjFTvg+RTElJdI+mUcuER04ddSduvfnSXPN/wmwLCTbiZOTC\n"
"NwMUGdXqapSqqdv+9poIZ4vvK7iqF0mDr8/LvOnP6pVxsLRFoszlh6oKw0E6eVza\n"
"UDSdlTs=\n"
"-----END CERTIFICATE-----\n";

const char* ZSignAsset::s_szAppleRootCACert = ""
"-----BEGIN CERTIFICATE-----\n"
"MIIEuzCCA6OgAwIBAgIBAjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzET\n"
"MBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlv\n"
"biBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDYwNDI1MjE0\n"
"MDM2WhcNMzUwMjA5MjE0MDM2WjBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBw\n"
"bGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkx\n"
"FjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw\n"
"ggEKAoIBAQDkkakJH5HbHkdQ6wXtXnmELes2oldMVeyLGYne+Uts9QerIjAC6Bg+\n"
"+FAJ039BqJj50cpmnCRrEdCju+QbKsMflZ56DKRHi1vUFjczy8QPTc4UadHJGXL1\n"
"XQ7Vf1+b8iUDulWPTV0N8WQ1IxVLFVkds5T39pyez1C6wVhQZ48ItCD3y6wsIG9w\n"
"tj8BMIy3Q88PnT3zK0koGsj+zrW5DtleHNbLPbU6rfQPDgCSC7EhFi501TwN22IW\n"
"q6NxkkdTVcGvL0Gz+PvjcM3mo0xFfh9Ma1CWQYnEdGILEINBhzOKgbEwWOxaBDKM\n"
"aLOPHd5lc/9nXmW8Sdh2nzMUZaF3lMktAgMBAAGjggF6MIIBdjAOBgNVHQ8BAf8E\n"
"BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUK9BpR5R2Cf70a40uQKb3\n"
"R01/CF4wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wggERBgNVHSAE\n"
"ggEIMIIBBDCCAQAGCSqGSIb3Y2QFATCB8jAqBggrBgEFBQcCARYeaHR0cHM6Ly93\n"
"d3cuYXBwbGUuY29tL2FwcGxlY2EvMIHDBggrBgEFBQcCAjCBthqBs1JlbGlhbmNl\n"
"IG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0\n"
"YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBj\n"
"b25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZp\n"
"Y2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMA0GCSqGSIb3DQEBBQUAA4IBAQBc\n"
"NplMLXi37Yyb3PN3m/J20ncwT8EfhYOFG5k9RzfyqZtAjizUsZAS2L70c5vu0mQP\n"
"y3lPNNiiPvl4/2vIB+x9OYOLUyDTOMSxv5pPCmv/K/xZpwUJfBdAVhEedNO3iyM7\n"
"R6PVbyTi69G3cN8PReEnyvFteO3ntRcXqNx+IjXKJdXZD9Zr1KIkIxH3oayPc4Fg\n"
"xhtbCS+SsvhESPBgOJ4V9T0mZyCKM2r3DYLP3uujL/lTaltkwGMzd/c6ByxW69oP\n"
"IQ7aunMZT7XZNn/Bh1XZp5m5MkL72NVxnn6hUrcbvZNCJBIqxw8dtk2cXmPIS4AX\n"
"UKqK1drk/NAJBzewdXUh\n"
"-----END CERTIFICATE-----\n";

// MARK: - DER

namespace {

string DerLength(size_t length)
{
	string out;
	if (length < 0x80) {
		out.push_back((char)length);
		return out;
	}
	string bytes;
	while (length > 0) {
		bytes.insert(bytes.begin(), (char)(length & 0xff));
		length >>= 8;
	}
	out.push_back((char)(0x80 | bytes.size()));
	out += bytes;
	return out;
}

string Tlv(uint8_t tag, const string& content)
{
	string out;
	out.push_back((char)tag);
	out += DerLength(content.size());
	out += content;
	return out;
}

string Sequence(const vector<string>& items)
{
	string content;
	for (const string& item : items) {
		content += item;
	}
	return Tlv(0x30, content);
}

// DER SET OF: elements sorted by their encodings.
string SetOf(vector<string> items, uint8_t tag = 0x31)
{
	sort(items.begin(), items.end(), [](const string& a, const string& b) {
		return lexicographical_compare(
			(const uint8_t*)a.data(), (const uint8_t*)a.data() + a.size(),
			(const uint8_t*)b.data(), (const uint8_t*)b.data() + b.size());
	});
	string content;
	for (const string& item : items) {
		content += item;
	}
	return Tlv(tag, content);
}

string ObjectIdentifier(const char* dotted)
{
	vector<uint64_t> parts;
	uint64_t value = 0;
	for (const char* p = dotted; ; p++) {
		if (*p == '.' || *p == 0) {
			parts.push_back(value);
			value = 0;
			if (*p == 0) {
				break;
			}
		} else {
			value = value * 10 + (uint64_t)(*p - '0');
		}
	}
	string body;
	body.push_back((char)(parts[0] * 40 + parts[1]));
	for (size_t i = 2; i < parts.size(); i++) {
		uint64_t part = parts[i];
		string chunk;
		chunk.insert(chunk.begin(), (char)(part & 0x7f));
		part >>= 7;
		while (part > 0) {
			chunk.insert(chunk.begin(), (char)(0x80 | (part & 0x7f)));
			part >>= 7;
		}
		body += chunk;
	}
	return Tlv(0x06, body);
}

string OctetString(const string& value)
{
	return Tlv(0x04, value);
}

string SmallInteger(uint8_t value)
{
	return Tlv(0x02, string(1, (char)value));
}

string Null()
{
	return string("\x05\x00", 2);
}

string UtcTimeNow()
{
	time_t now = time(NULL);
	struct tm utc;
	gmtime_r(&now, &utc);
	char buffer[16] = { 0 };
	strftime(buffer, sizeof(buffer), "%y%m%d%H%M%SZ", &utc);
	return Tlv(0x17, buffer);
}

string Attribute(const char* oid, const string& value)
{
	return Sequence({ ObjectIdentifier(oid), SetOf({ value }) });
}

// Definite-length DER only (certificates are DER).
bool ReadTlv(const string& buffer, size_t position, size_t& contentStart, size_t& contentLength)
{
	if (position + 2 > buffer.size()) {
		return false;
	}
	size_t cursor = position + 1;
	uint8_t first = (uint8_t)buffer[cursor++];
	if (first < 0x80) {
		contentLength = first;
	} else {
		size_t count = first & 0x7f;
		if (count == 0 || count > 4 || cursor + count > buffer.size()) {
			return false;
		}
		contentLength = 0;
		for (size_t i = 0; i < count; i++) {
			contentLength = (contentLength << 8) | (uint8_t)buffer[cursor++];
		}
	}
	contentStart = cursor;
	return contentStart + contentLength <= buffer.size();
}

// The raw issuer Name, serialNumber INTEGER and subject Name of an X.509 certificate.
bool CertificateFields(const string& certificate, string& issuer, string& serial, string& subject)
{
	size_t start = 0, length = 0;
	if (!ReadTlv(certificate, 0, start, length)) { // Certificate
		return false;
	}
	if (!ReadTlv(certificate, start, start, length)) { // TBSCertificate
		return false;
	}
	size_t cursor = start;
	auto next = [&](string* out) -> bool {
		size_t contentStart = 0, contentLength = 0;
		if (!ReadTlv(certificate, cursor, contentStart, contentLength)) {
			return false;
		}
		size_t end = contentStart + contentLength;
		if (out) {
			*out = certificate.substr(cursor, end - cursor);
		}
		cursor = end;
		return true;
	};
	if ((uint8_t)certificate[cursor] == 0xA0) { // [0] version
		if (!next(NULL)) {
			return false;
		}
	}
	return next(&serial) && next(NULL) && next(&issuer) && next(NULL) && next(&subject);
}

string PemToDer(const char* pem)
{
	NSString* text = [NSString stringWithUTF8String:pem];
	NSMutableString* body = [NSMutableString string];
	for (NSString* line in [text componentsSeparatedByString:@"\n"]) {
		if (![line hasPrefix:@"-----"]) {
			[body appendString:line];
		}
	}
	NSData* data = [[NSData alloc] initWithBase64EncodedString:body options:NSDataBase64DecodingIgnoreUnknownCharacters];
	return data ? string((const char*)data.bytes, data.length) : string();
}

string StringFromData(NSData* data)
{
	return data ? string((const char*)data.bytes, data.length) : string();
}

NSData* DataFromString(const string& value)
{
	return [NSData dataWithBytes:value.data() length:value.size()];
}

} // namespace

// MARK: - ZSignAsset

bool ZSignAsset::CMSError()
{
	ZLog::Error(">>> CMS error\n");
	return false;
}

// The embedded plist of a provisioning profile (CMS SignedData with the plist as content).
bool ZSignAsset::GetCMSContent(const string& strCMSDataInput, string& strContentOutput)
{
	size_t start = strCMSDataInput.find("<?xml");
	if (string::npos == start) {
		start = strCMSDataInput.find("<plist");
	}
	if (string::npos == start) {
		return false;
	}
	const string closing = "</plist>";
	size_t end = strCMSDataInput.find(closing, start);
	if (string::npos == end) {
		return false;
	}
	strContentOutput = strCMSDataInput.substr(start, end + closing.size() - start);
	return true;
}

// Only used to print an existing signature; not needed on device.
bool ZSignAsset::GetCMSInfo(uint8_t* pCMSData, uint32_t uCMSLength, jvalue& jvOutput)
{
	return false;
}

ZSignAsset::ZSignAsset()
{
	m_evpPKey = NULL;
	m_x509Cert = NULL;
	m_bAdhoc = false;
	m_bSingleBinary = false;
	m_bSHA256Only = false;
}

bool ZSignAsset::Init(
	const string& strCertFile,
	const string& strPKeyFile,
	const string& strProvFile,
	const string& strEntitleFile,
	const string& strPassword,
	bool bAdhoc,
	bool bSHA256Only,
	bool bSingleBinary)
{
	m_bAdhoc = bAdhoc;
	m_bSHA256Only = bSHA256Only;
	m_bSingleBinary = bSingleBinary;

	if (m_bAdhoc) {
		if (!strEntitleFile.empty()) {
			if (!ZFile::ReadFile(strEntitleFile.c_str(), m_strEntitleData)) {
				ZLog::Error(">>> Can't read entitlements file!\n");
				return false;
			}
		}
		return true;
	}

	ZFile::ReadFile(strProvFile.c_str(), m_strProvData);
	if (!strEntitleFile.empty()) {
		ZFile::ReadFile(strEntitleFile.c_str(), m_strEntitleData);
	}
	if (m_strProvData.empty()) {
		ZLog::Error("Не удалось прочитать .mobileprovision\n");
		return false;
	}

	jvalue jvProv;
	string strProvContent;
	if (GetCMSContent(m_strProvData, strProvContent)) {
		if (jvProv.read_plist(strProvContent)) {
			m_strApplicationId = jvProv["Entitlements"]["application-identifier"].as_cstr();
			m_strTeamId = jvProv["TeamIdentifier"][0].as_cstr();
			if (m_strEntitleData.empty()) {
				jvProv["Entitlements"].style_write_plist(m_strEntitleData);
			}
		}
	}

	if (m_strTeamId.empty()) {
		ZLog::Error("В .mobileprovision нет Team ID — файл повреждён или это не профиль\n");
		return false;
	}

	string strP12Data;
	ZFile::ReadFile(strPKeyFile.c_str(), strP12Data);
	if (strP12Data.empty()) {
		ZLog::Error("Не удалось прочитать .p12\n");
		return false;
	}

	@autoreleasepool {
		NSString* password = [NSString stringWithUTF8String:strPassword.c_str()] ?: @"";
		NSDictionary* options = @{ (__bridge id)kSecImportExportPassphrase: password };
		CFArrayRef items = NULL;
		OSStatus status = SecPKCS12Import((__bridge CFDataRef)DataFromString(strP12Data), (__bridge CFDictionaryRef)options, &items);
		NSArray* importedItems = CFBridgingRelease(items);
		if (status == errSecAuthFailed) {
			ZLog::Error("Неверный пароль от .p12\n");
			return false;
		}
		if (status != errSecSuccess || importedItems.count == 0) {
			ZLog::ErrorV("Не удалось открыть .p12 (код %d)\n", (int)status);
			return false;
		}
		NSDictionary* item = importedItems.firstObject;
		SecIdentityRef identity = (__bridge SecIdentityRef)item[(__bridge id)kSecImportItemIdentity];
		if (identity == NULL) {
			ZLog::Error("В .p12 нет сертификата с ключом\n");
			return false;
		}
		SecCertificateRef certificate = NULL;
		SecKeyRef privateKey = NULL;
		if (SecIdentityCopyCertificate(identity, &certificate) != errSecSuccess || certificate == NULL) {
			ZLog::Error("В .p12 нет сертификата\n");
			return false;
		}
		if (SecIdentityCopyPrivateKey(identity, &privateKey) != errSecSuccess || privateKey == NULL) {
			CFRelease(certificate);
			ZLog::Error("В .p12 нет закрытого ключа\n");
			return false;
		}

		string strCertData = StringFromData(CFBridgingRelease(SecCertificateCopyData(certificate)));
		bool bInProfile = false;
		for (size_t i = 0; i < jvProv["DeveloperCertificates"].size(); i++) {
			if (jvProv["DeveloperCertificates"][i].as_data() == strCertData) {
				bInProfile = true;
				break;
			}
		}
		if (!bInProfile) {
			CFRelease(certificate);
			CFRelease(privateKey);
			ZLog::Error("Сертификат из .p12 не входит в этот .mobileprovision — нужна пара от одного сертификата\n");
			return false;
		}

		CFStringRef commonName = NULL;
		SecCertificateCopyCommonName(certificate, &commonName);
		NSString* subjectCN = CFBridgingRelease(commonName);
		if (subjectCN.length == 0) {
			CFRelease(certificate);
			CFRelease(privateKey);
			ZLog::Error("У сертификата нет имени (CN)\n");
			return false;
		}
		m_strSubjectCN = subjectCN.UTF8String;

		// Owned by this asset for the whole signing run.
		m_x509Cert = (void*)certificate;
		m_evpPKey = (void*)privateKey;
	}
	return true;
}

bool ZSignAsset::GenerateCMS(const string& strCDHashData, const string& strCDHashesPlist, const string& strCodeDirectorySlotSHA1, const string& strAltnateCodeDirectorySlot256, string& strCMSOutput)
{
	return GenerateCMS(m_x509Cert, m_evpPKey, strCDHashData, strCDHashesPlist, strCodeDirectorySlotSHA1, strAltnateCodeDirectorySlot256, strCMSOutput);
}

// Detached CMS SignedData over the first CodeDirectory, the same layout OpenSSL's
// CMS_sign produces in upstream zsign: signer cert + Apple WWDR + Apple Root CA,
// signed attributes contentType, signingTime, messageDigest (SHA-256), the
// CDHashes plist (1.2.840.113635.100.9.1) and CDHashes2 (1.2.840.113635.100.9.2).
bool ZSignAsset::GenerateCMS(void* pscert, void* pspkey, const string& strCDHashData, const string& strCDHashesPlist, const string& strCodeDirectorySlotSHA1, const string& strAltnateCodeDirectorySlot256, string& strCMSOutput)
{
	if (!pscert || !pspkey) {
		return CMSError();
	}
	SecCertificateRef certificate = (SecCertificateRef)pscert;
	SecKeyRef privateKey = (SecKeyRef)pspkey;

	@autoreleasepool {
		string strCertData = StringFromData(CFBridgingRelease(SecCertificateCopyData(certificate)));
		string issuer, serial, subject;
		if (!CertificateFields(strCertData, issuer, serial, subject)) {
			ZLog::Error("Не удалось разобрать сертификат подписи\n");
			return false;
		}

		string strWWDRG3 = PemToDer(s_szAppleDevCACertG3);
		string strWWDRG1 = PemToDer(s_szAppleDevCACert);
		string strRoot = PemToDer(s_szAppleRootCACert);
		string strIntermediate = strWWDRG3;
		string intermediateIssuer, intermediateSerial, intermediateSubject;
		if (CertificateFields(strWWDRG1, intermediateIssuer, intermediateSerial, intermediateSubject) && intermediateSubject == issuer) {
			strIntermediate = strWWDRG1;
		}

		const char* sha256Oid = "2.16.840.1.101.3.4.2.1";
		string sha256Algorithm = Sequence({ ObjectIdentifier(sha256Oid) });

		uint8_t digest[CC_SHA256_DIGEST_LENGTH];
		CC_SHA256(strCDHashData.data(), (CC_LONG)strCDHashData.size(), digest);
		string messageDigest((const char*)digest, sizeof(digest));

		vector<string> attributes = {
			Attribute("1.2.840.113549.1.9.3", ObjectIdentifier("1.2.840.113549.1.7.1")),
			Attribute("1.2.840.113549.1.9.5", UtcTimeNow()),
			Attribute("1.2.840.113549.1.9.4", OctetString(messageDigest)),
			Attribute("1.2.840.113635.100.9.1", OctetString(strCDHashesPlist)),
			Attribute("1.2.840.113635.100.9.2", Sequence({ ObjectIdentifier(sha256Oid), OctetString(strAltnateCodeDirectorySlot256) })),
		};
		// Signed as a SET (tag 0x31), stored as [0] IMPLICIT.
		string signedAttributes = SetOf(attributes);
		string signedAttributesImplicit = signedAttributes;
		signedAttributesImplicit[0] = (char)0xA0;

		NSDictionary* keyAttributes = CFBridgingRelease(SecKeyCopyAttributes(privateKey));
		BOOL isEC = [keyAttributes[(__bridge id)kSecAttrKeyType] isEqual:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom];
		SecKeyAlgorithm algorithm = isEC ? kSecKeyAlgorithmECDSASignatureMessageX962SHA256 : kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
		string signatureAlgorithm = isEC
			? Sequence({ ObjectIdentifier("1.2.840.10045.4.3.2") })
			: Sequence({ ObjectIdentifier("1.2.840.113549.1.1.1"), Null() });

		CFErrorRef error = NULL;
		NSData* signature = CFBridgingRelease(SecKeyCreateSignature(privateKey, algorithm, (__bridge CFDataRef)DataFromString(signedAttributes), &error));
		if (signature == nil) {
			NSError* signError = CFBridgingRelease(error);
			ZLog::ErrorV("Ключ из .p12 не смог подписать: %s\n", signError.localizedDescription.UTF8String ?: "?");
			return false;
		}

		string signerInfo = Sequence({
			SmallInteger(1),
			Sequence({ issuer, serial }),
			sha256Algorithm,
			signedAttributesImplicit,
			signatureAlgorithm,
			OctetString(StringFromData(signature)),
		});
		string signedData = Sequence({
			SmallInteger(1),
			SetOf({ sha256Algorithm }),
			Sequence({ ObjectIdentifier("1.2.840.113549.1.7.1") }),
			SetOf({ strCertData, strIntermediate, strRoot }, 0xA0),
			SetOf({ signerInfo }),
		});
		strCMSOutput = Sequence({ ObjectIdentifier("1.2.840.113549.1.7.2"), Tlv(0xA0, signedData) });
	}
	return !strCMSOutput.empty();
}
