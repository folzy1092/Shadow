// Shadow: zsign only needs one-shot SHA-1/SHA-256 from OpenSSL. Telegram's
// own OpenSSL build is minimal (no CMS/RC2/DES) and a second OpenSSL would
// clash with its symbols, so these come from CommonCrypto instead.
#pragma once

#include <CommonCrypto/CommonDigest.h>
#include <stddef.h>
#include <stdint.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
// Code signatures still carry SHA-1 slots; this is not used for security.
static inline unsigned char* SHA1(const unsigned char* data, size_t size, unsigned char* md)
{
	CC_SHA1(data, (CC_LONG)size, md);
	return md;
}
#pragma clang diagnostic pop

static inline unsigned char* SHA256(const unsigned char* data, size_t size, unsigned char* md)
{
	CC_SHA256(data, (CC_LONG)size, md);
	return md;
}
