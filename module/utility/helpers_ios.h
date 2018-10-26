#ifndef MODULES_UTILITY_HELPERS_IOS_H_
#define MODULES_UTILITY_HELPERS_IOS_H_

#ifdef __APPLE__

#include <string>

bool CheckAndLogError(BOOL success, NSError* error);

std::string StdStringFromNSString(NSString* nsString);

// Return thread ID as a string.
std::string GetThreadId();

// Return thread ID as string suitable for debug logging.
std::string GetThreadInfo();

// Returns [NSThread currentThread] description as string.
// Example: <NSThread: 0x170066d80>{number = 1, name = main}
std::string GetCurrentThreadDescription();

std::string GetAudioSessionCategory();

// Returns the current name of the operating system.
std::string GetSystemName();

// Returns the current version of the operating system.
std::string GetSystemVersion();

// Returns the version of the operating system as a floating point value.
float GetSystemVersionAsFloat();

// Returns the device type.
// Examples: ”iPhone” and ”iPod touch”.
std::string GetDeviceType();

// Returns a more detailed device name.
// Examples: "iPhone 5s (GSM)" and "iPhone 6 Plus".
std::string GetDeviceName();

// Returns the name of the process. Does not uniquely identify the process.
std::string GetProcessName();

// Returns the identifier of the process (often called process ID).
int GetProcessID();

// Returns a string containing the version of the operating system on which the
// process is executing. The string is string is human readable, localized, and
// is appropriate for displaying to the user.
std::string GetOSVersionString();

// Returns the number of processing cores available on the device.
int GetProcessorCount();

// Indicates whether Low Power Mode is enabled on the iOS device.
bool GetLowPowerModeEnabled();

#endif  // __APPLE__

#endif  // MODULES_UTILITY_HELPERS_IOS_H_
