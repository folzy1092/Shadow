#import <Zsign/ShadowZsign.h>

#include "common.h"
#include "bundle.h"
#include "openssl.h"

#include <mutex>

namespace {

// zsign keeps global state (log level, last error); one signing at a time.
std::mutex& SigningMutex()
{
	static std::mutex mutex;
	return mutex;
}

NSString* LastErrorOr(NSString* fallback)
{
	string text = ZLog::LastError();
	while (!text.empty() && (text.back() == '\n' || text.back() == ' ')) {
		text.pop_back();
	}
	if (text.rfind(">>> ", 0) == 0) {
		text = text.substr(4);
	}
	NSString* message = text.empty() ? nil : [NSString stringWithUTF8String:text.c_str()];
	return message.length > 0 ? message : fallback;
}

} // namespace

@implementation ShadowZsign

+ (NSString *)signAppAtPath:(NSString *)appPath provisionPath:(NSString *)provisionPath p12Path:(NSString *)p12Path password:(NSString *)password
{
	std::lock_guard<std::mutex> lock(SigningMutex());
	ZLog::SetLogLever(ZLog::E_ERROR);
	ZLog::ClearLastError();

	ZSignAsset asset;
	if (!asset.Init("", p12Path.UTF8String, provisionPath.UTF8String, "", password.UTF8String ?: "", false, false, false)) {
		return LastErrorOr(@"Не удалось загрузить сертификат и профиль");
	}

	ZBundle bundle;
	vector<string> noDylibs;
	// bForce: sign every binary; no cache (it writes to the working directory);
	// last argument true = write embedded.mobileprovision.
	bool signedOK = bundle.SignFolder(&asset, appPath.UTF8String, "", "", "", noDylibs, noDylibs, true, false, false, true);
	if (!signedOK) {
		return LastErrorOr(@"Подпись не удалась");
	}
	return nil;
}

+ (NSString *)checkProvisionPath:(NSString *)provisionPath p12Path:(NSString *)p12Path password:(NSString *)password
{
	std::lock_guard<std::mutex> lock(SigningMutex());
	ZLog::SetLogLever(ZLog::E_ERROR);
	ZLog::ClearLastError();

	ZSignAsset asset;
	if (!asset.Init("", p12Path.UTF8String, provisionPath.UTF8String, "", password.UTF8String ?: "", false, false, false)) {
		return LastErrorOr(@"Не удалось загрузить сертификат и профиль");
	}
	return nil;
}

@end
