// Shadow: PKCS#12 reader on CommonCrypto for the files SecPKCS12Import
// rejects with errSecDecode (-26275): OpenSSL 3 exports use PBES2 + PBKDF2
// (HMAC-SHA-256) + AES-256-CBC and a SHA-256 MAC. Also reads the legacy PBEs
// (SHA-1 3DES / RC2). Logic checked against openssl-made files in Python.
#pragma once

#include <string>
#include <vector>

// privateKeyInfo: DER PKCS#8 PrivateKeyInfo of the first key; certificates:
// DER X.509 of every certificate bag. wrongPassword is set when the MAC (or,
// without a MAC, the padding) does not match the password.
bool ShadowParsePKCS12(const std::string& p12,
                       const std::string& password,
                       std::string& privateKeyInfo,
                       std::vector<std::string>& certificates,
                       bool& wrongPassword,
                       std::string& error);

// RSAPrivateKey (PKCS#1) inside an RSA PrivateKeyInfo; false for other keys.
bool ShadowRSAKeyFromPKCS8(const std::string& privateKeyInfo, std::string& rsaPrivateKey);
