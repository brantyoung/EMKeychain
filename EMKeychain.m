/*Copyright (c) 2007 Extendmac, LLC. <support@extendmac.com>
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */

#import "EMKeychain.h"

@interface EMKeychainItem (Private)
- (BOOL)modifyAttributeWithTag:(SecItemAttr)attributeTag toBeString:(NSString *)newStringValue;
@end

@implementation EMKeychainItem

static BOOL _logErrors;

+ (void)lockKeychain {
	SecKeychainLock(NULL);
}
+ (void)unlockKeychain {
	SecKeychainUnlock(NULL, 0, NULL, NO);
}
+ (void)setLogsErrors:(BOOL)flag {
	_logErrors = flag;
}

+ (void)removeKeychainItem:(EMKeychainItem *)keychainItem {
	[keychainItem remove];
}

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item username:(NSString *)username password:(NSString *)password {
	if ((self = [super init])) 	{
		coreKeychainItem = item;
		[self setValue:username forKey:@"myUsername"];
		[self setValue:password forKey:@"myPassword"];
	}
	return self;
}

- (NSString *)password {
	return myPassword;
}
- (NSString *)username {
	return myUsername;
}
- (NSString *)label {
	return myLabel;
}

- (BOOL)setPassword:(NSString *)newPasswordString {
	if (!newPasswordString)
		return NO;
	
	[self willChangeValueForKey:@"password"];
	myPassword = newPasswordString;
	[self didChangeValueForKey:@"password"];
	
	const char *newPassword = [newPasswordString UTF8String];
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, NULL, (UInt32)strlen(newPassword), (void *)newPassword);
	return (returnStatus == noErr);	
}
- (BOOL)setUsername:(NSString *)newUsername {
	[self willChangeValueForKey:@"username"];
	myUsername = newUsername;
	[self didChangeValueForKey:@"username"];	
	
	return [self modifyAttributeWithTag:kSecAccountItemAttr toBeString:newUsername];
}
- (BOOL)setLabel:(NSString *)newLabel {
	[self willChangeValueForKey:@"label"];
	myLabel = newLabel;
	[self didChangeValueForKey:@"label"];
	
	return [self modifyAttributeWithTag:kSecLabelItemAttr toBeString:newLabel];
}
- (void)remove {
  	SecKeychainItemDelete(coreKeychainItem);
}
- (void)dealloc {
	if (coreKeychainItem) CFRelease(coreKeychainItem);
}
@end

@implementation EMKeychainItem (Private)
- (BOOL)modifyAttributeWithTag:(SecItemAttr)attributeTag toBeString:(NSString *)newStringValue {
	const char *newValue = [newStringValue UTF8String];
	SecKeychainAttribute attributes[1];
	attributes[0].tag = attributeTag;
	attributes[0].length = (UInt32)strlen(newValue);
	attributes[0].data = (void *)newValue;
	
	SecKeychainAttributeList list;
	list.count = 1;
	list.attr = attributes;
	
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, &list, 0, NULL);
	return (returnStatus == noErr);
}
@end

@implementation EMGenericKeychainItem

+ (EMGenericKeychainItem *)genericKeychainItemForService:(NSString *)serviceNameString withUsername:(NSString *)usernameString {
	if (!usernameString || [usernameString length] == 0)
		return nil;
	
	const char *serviceName = [serviceNameString UTF8String];
	const char *username = [usernameString UTF8String];
	
	UInt32 passwordLength = 0;
	char *password = nil;
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainFindGenericPassword(NULL, (UInt32)strlen(serviceName), serviceName, (UInt32)strlen(username), username, &passwordLength, (void **)&password, &item);
	if (returnStatus != noErr || !item) 	{
		if (_logErrors) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:returnStatus userInfo:nil];
			NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), error.localizedDescription);
        }

		return nil;
	}
	
	char passwordStore[1024];
	if (passwordLength > 1023) {
		passwordLength = 1023; // save room for trailing \0
	}
	strncpy (passwordStore, password, passwordLength);
	
	passwordStore[passwordLength] = '\0';
	NSString *passwordString = [NSString stringWithUTF8String:passwordStore];

	SecKeychainItemFreeContent(NULL, password);
	
	return [EMGenericKeychainItem genericKeychainItem:item forServiceName:serviceNameString username:usernameString password:passwordString];
}

+ (EMGenericKeychainItem *)addGenericKeychainItemForService:(NSString *)serviceNameString withUsername:(NSString *)usernameString password:(NSString *)passwordString {
	if (!usernameString || [usernameString length] == 0 || !serviceNameString || [serviceNameString length] == 0)
		return nil;
	
	const char *serviceName = [serviceNameString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *password = [passwordString UTF8String];
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainAddGenericPassword(NULL, (UInt32)strlen(serviceName), serviceName, (UInt32)strlen(username), username, (UInt32)strlen(password), (void *)password, &item);
	
	if (returnStatus != noErr || !item) {
        CFStringRef errDesc = SecCopyErrorMessageString(returnStatus, NULL);
		NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), errDesc);
        CFRelease(errDesc);
		return nil;
	}
	return [EMGenericKeychainItem genericKeychainItem:item forServiceName:serviceNameString username:usernameString password:passwordString];
}

+ (void) setKeychainPassword:(NSString*)password forUsername:(NSString*)username service:(NSString*)serviceName {
	EMKeychainItem *item = [EMGenericKeychainItem genericKeychainItemForService:serviceName withUsername:username];
	if (item == nil)
		[EMGenericKeychainItem addGenericKeychainItemForService:serviceName withUsername:username password:password];
	else
		[item setPassword:password];
}

+ (NSString*) passwordForUsername:(NSString*)username service:(NSString*)serviceName {
	return [[EMGenericKeychainItem genericKeychainItemForService:serviceName withUsername:username] password];
}

// generic keychain item for service
// returns first item matching the service criteria.
+ (EMGenericKeychainItem *)genericKeychainItemForService:(NSString *)serviceNameString
{
	const char *serviceName = [serviceNameString UTF8String];
	
	UInt32 passwordLength = 0;
	char *password = nil;
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainFindGenericPassword(NULL, (UInt32)strlen(serviceName), serviceName, 0, NULL, &passwordLength, (void **)&password, &item);
	if (returnStatus != noErr || !item) {
		if (_logErrors) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:returnStatus userInfo:nil];
			NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), error.localizedDescription);
		}
		return nil;
	}
	NSString *passwordString = [NSString stringWithCString:password encoding:NSUTF8StringEncoding];
	SecKeychainItemFreeContent(NULL, password);	// free the password data
	
	// search sec item for account name
	SecKeychainAttribute attributes[2];
	SecKeychainAttributeList list;
	attributes[0].tag = kSecAccountItemAttr;
	list.count = 1;
	list.attr = attributes;
	
	returnStatus = SecKeychainItemCopyContent(item, NULL, &list, NULL, NULL);
	if (returnStatus != noErr) {
		if (_logErrors) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:returnStatus userInfo:nil];
			NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), error.localizedDescription);
		}
		return nil;
	}
	
	// get the attribute data
	SecKeychainAttribute attr;
	attr = list.attr[0];
	char buffer[1024];
	strncpy(buffer, attr.data, attr.length);
	buffer[attr.length] = '\0';
	
	// get the username
	NSString *usernameString = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    
	SecKeychainItemFreeContent(&list, NULL);	// free the list
	
	return [EMGenericKeychainItem genericKeychainItem:item forServiceName:serviceNameString username:usernameString password:passwordString];
}

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item serviceName:(NSString *)serviceName username:(NSString *)username password:(NSString *)password {
	if ((self = [super initWithCoreKeychainItem:item username:username password:password]))
    {
		[self setValue:serviceName forKey:@"myServiceName"];
	}
	return self;
}

+ (id)genericKeychainItem:(SecKeychainItemRef)item forServiceName:(NSString *)serviceName username:(NSString *)username password:(NSString *)password
{
	return [[EMGenericKeychainItem alloc] initWithCoreKeychainItem:item serviceName:serviceName username:username password:password];
}

- (NSString *)serviceName {
	return myServiceName;
}

- (BOOL)setServiceName:(NSString *)newServiceName
{
	[self willChangeValueForKey:@"serviceName"];
	myServiceName = newServiceName;
	[self didChangeValueForKey:@"serviceName"];	
	
	return [self modifyAttributeWithTag:kSecServiceItemAttr toBeString:newServiceName];
}

@end

@implementation EMInternetKeychainItem

+ (EMInternetKeychainItem *)internetKeychainItemForServer:(NSString *)serverString withUsername:(NSString *)usernameString path:(NSString *)pathString port:(UInt16)port protocol:(SecProtocolType)protocol {
	if (!usernameString || [usernameString length] == 0 || !serverString || [serverString length] == 0)
		return nil;
	
	const char *server = [serverString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *path = [pathString UTF8String];
	
	if (!pathString || [pathString length] == 0)
		path = "";
	
	UInt32 passwordLength = 0;
	char *password = nil;
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainFindInternetPassword(NULL, (UInt32)strlen(server), server, 0, NULL, (UInt32)strlen(username), username, (UInt32)strlen(path), path, port, protocol, kSecAuthenticationTypeDefault, &passwordLength, (void **)&password, &item);
	
	if (returnStatus != noErr || !item) {
		if (_logErrors) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:returnStatus userInfo:nil];
			NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), error.localizedDescription);
        }
		
		return nil;
	}
	char passwordStore[1024];
	if (passwordLength > 1023) {
		passwordLength = 1023; // save room for trailing \0
	}
	strncpy (passwordStore, password, passwordLength);
	
	passwordStore[passwordLength] = '\0';
	NSString *passwordString = [NSString stringWithUTF8String:passwordStore];
	
	SecKeychainItemFreeContent(NULL, password);
	
	return [EMInternetKeychainItem internetKeychainItem:item forServer:serverString username:usernameString password:passwordString path:pathString port:port protocol:protocol];
}

+ (EMInternetKeychainItem *)addInternetKeychainItemForServer:(NSString *)serverString withUsername:(NSString *)usernameString password:(NSString *)passwordString path:(NSString *)pathString port:(UInt16)port protocol:(SecProtocolType)protocol {
	if (!usernameString || [usernameString length] == 0 || !serverString || [serverString length] == 0 || !passwordString || [passwordString length] == 0)
		return nil;
	
	const char *server = [serverString UTF8String];
	const char *username = [usernameString UTF8String];
	const char *password = [passwordString UTF8String];
	const char *path = [pathString UTF8String];
	
	if (!pathString || [pathString length] == 0)
		path = "";
	
	SecKeychainItemRef item = nil;
	OSStatus returnStatus = SecKeychainAddInternetPassword(NULL, (UInt32)strlen(server), server, 0, NULL, (UInt32)strlen(username), username, (UInt32)strlen(path), path, port, protocol, kSecAuthenticationTypeDefault, (UInt32)strlen(password), (void *)password, &item);
	
	if (returnStatus != noErr || !item) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:returnStatus userInfo:nil];
        NSLog(@"Error (%@) - %@", NSStringFromSelector(_cmd), error.localizedDescription);
		return nil;
	}
	return [EMInternetKeychainItem internetKeychainItem:item forServer:serverString username:usernameString password:passwordString path:pathString port:port protocol:protocol];
}

- (id)initWithCoreKeychainItem:(SecKeychainItemRef)item server:(NSString *)server username:(NSString *)username password:(NSString *)password path:(NSString *)path port:(UInt16)port protocol:(SecProtocolType)protocol {
	if ((self = [super initWithCoreKeychainItem:item username:username password:password])) {
		[self setValue:server forKey:@"myServer"];
		[self setValue:path forKey:@"myPath"];
		[self setValue:[NSNumber numberWithInt:port] forKey:@"myPort"];
		[self setValue:[NSNumber numberWithInt:protocol] forKey:@"myProtocol"];
	}
	return self;
}
+ (id)internetKeychainItem:(SecKeychainItemRef)item forServer:(NSString *)server username:(NSString *)username password:(NSString *)password path:(NSString *)path port:(UInt16)port protocol:(SecProtocolType)protocol {
	return [[EMInternetKeychainItem alloc] initWithCoreKeychainItem:item server:server username:username password:password path:path port:port protocol:protocol];
}
- (NSString *)server {
	return myServer;
}
- (NSString *)path {
	return myPath;
}
- (UInt16)port {
	return myPort;
}
- (SecProtocolType)protocol {
	return myProtocol;
}

- (BOOL)setServer:(NSString *)newServer {
	[self willChangeValueForKey:@"server"];
	myServer = newServer;
	[self didChangeValueForKey:@"server"];
	
	return [self modifyAttributeWithTag:kSecServerItemAttr toBeString:newServer];
}
- (BOOL)setPath:(NSString *)newPath {
	[self willChangeValueForKey:@"path"];
	myPath = newPath;
	[self didChangeValueForKey:@"path"];
	
	return [self modifyAttributeWithTag:kSecPathItemAttr toBeString:newPath];
}
- (BOOL)setPort:(UInt16)newPort {
	[self willChangeValueForKey:@"port"];
	myPort = newPort;
	[self didChangeValueForKey:@"port"];
	
	return [self modifyAttributeWithTag:kSecPortItemAttr toBeString:[NSString stringWithFormat:@"%i", newPort]];
}
- (BOOL)setProtocol:(SecProtocolType)newProtocol {
	[self willChangeValueForKey:@"protocol"];
	myProtocol = newProtocol;
	[self didChangeValueForKey:@"protocol"];
	
	//	need to explictly cast to a void* 
	void *protocalPointer;
	memcpy(&protocalPointer, &newProtocol, sizeof newProtocol);
	
	SecKeychainAttribute attributes[1];
	attributes[0].tag = kSecProtocolItemAttr;
	attributes[0].length = sizeof(newProtocol);
	attributes[0].data = &protocalPointer;
	
	SecKeychainAttributeList list;
	list.count = 1;
	list.attr = attributes;
	
	OSStatus returnStatus = SecKeychainItemModifyAttributesAndData(coreKeychainItem, &list, 0, NULL);
	return (returnStatus == noErr);
}

@end
