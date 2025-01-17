// Copyright (c) 2017-2019 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "../SafariPlus.h"

#import "../Util.h"
#import "../Defines.h"
#import "../Classes/SPDownloadManager.h"
#import "../Classes/SPPreferenceManager.h"
#import "../Classes/SPLocalizationManager.h"
#import "../Classes/SPCacheManager.h"
#import "../Classes/SPCommunicationManager.h"
#import "../Shared/SPPreferenceUpdater.h"

#import <UserNotifications/UserNotifications.h>

%hook Application

%property (nonatomic,assign) BOOL sp_isSetUp;
%property (nonatomic,retain) NSDictionary* sp_storedLaunchOptions;

%new
- (void)sp_preAppLaunch
{
	#ifndef SIMJECT
	[SPPreferenceUpdater update];
	#endif
}

%new
- (void)sp_postAppLaunchWithOptions:(NSDictionary*)launchOptions
{
	self.sp_storedLaunchOptions = launchOptions;

	[self handleSBConnectionTest];

	if(preferenceManager.downloadManagerEnabled)
	{
		downloadManager = [SPDownloadManager sharedInstance];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"SPDownloadManagerDidInitNotification" object:nil];

		if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_10_0)
		{
			UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
			UNAuthorizationOptions options = UNAuthorizationOptionAlert + UNAuthorizationOptionSound;
			[center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error){}];
		}
		else
		{
			UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert) categories:nil];
			[self registerUserNotificationSettings:settings];
		}
	}

	if(!preferenceManager.applicationBadgeEnabled && self.applicationIconBadgeNumber > 0)
	{
		self.applicationIconBadgeNumber = 0;
	}

	[self sp_setUpWithMainBrowserController:browserControllers().firstObject];
}

%new
- (void)sp_setUpWithMainBrowserController:(BrowserController*)mainBrowserController
{
	if(mainBrowserController && !self.sp_isSetUp)
	{
		//Auto switch mode on launch
		if(preferenceManager.forceModeOnStartEnabled && !self.sp_storedLaunchOptions[UIApplicationLaunchOptionsURLKey])
		{
			for(BrowserController* controller in browserControllers())
			{
				//Switch mode to specified mode
				[controller modeSwitchAction:preferenceManager.forceModeOnStartFor];
			}
		}

		if(preferenceManager.lockedTabsEnabled)
		{
			[cacheManager cleanUpTabStateAdditions];
		}

		[self handleTwitterAlert];

		self.sp_isSetUp = YES;
		self.sp_storedLaunchOptions = nil;
	}
}

%new
- (void)handleTwitterAlert
{
	if([cacheManager firstStart])
	{
		BrowserController* browserController = browserControllers().firstObject;

		UIAlertController* welcomeAlert = [UIAlertController alertControllerWithTitle:[localizationManager localizedSPStringForKey:@"WELCOME_TITLE"]
						   message:[localizationManager localizedSPStringForKey:@"WELCOME_MESSAGE"]
						   preferredStyle:UIAlertControllerStyleAlert];

		UIAlertAction* closeAction = [UIAlertAction actionWithTitle:[localizationManager localizedSPStringForKey:@"CLOSE"]
					      style:UIAlertActionStyleDefault
					      handler:nil];

		UIAlertAction* openAction = [UIAlertAction actionWithTitle:[localizationManager localizedSPStringForKey:@"OPEN_TWITTER"]
					     style:UIAlertActionStyleDefault
					     handler:^(UIAlertAction * action)
		{
			//Twitter is installed as an application
			if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]])
			{
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"twitter://user?screen_name=opa334dev"]];
			}
			//Twitter is not installed, open web page
			else
			{
				NSURL* twitterURL = [NSURL URLWithString:@"https://twitter.com/opa334dev"];

				if([browserController respondsToSelector:@selector(loadURLInNewTab:inBackground:animated:)])
				{
					[browserController loadURLInNewTab:twitterURL inBackground:NO animated:YES];
				}
				else
				{
					[browserController loadURLInNewWindow:twitterURL inBackground:NO animated:YES];
				}
			}
		}];

		[welcomeAlert addAction:closeAction];
		[welcomeAlert addAction:openAction];

		if([welcomeAlert respondsToSelector:@selector(preferredAction)])
		{
			welcomeAlert.preferredAction = openAction;
		}

		[cacheManager firstStartDidSucceed];

		dispatch_async(dispatch_get_main_queue(), ^
		{
			[rootViewControllerForBrowserController(browserController) presentViewController:welcomeAlert animated:YES completion:nil];
		});
	}
}

//Tests whether Safari is able to communicate with SpringBoard
%new
- (void)handleSBConnectionTest
{
	rocketBootstrapWorks = [communicationManager testConnection];

	if(!rocketBootstrapWorks && !preferenceManager.communicationErrorDisabled)
	{
		sendSimpleAlert([localizationManager localizedSPStringForKey:@"COMMUNICATION_ERROR"], [localizationManager localizedSPStringForKey:@"COMMUNICATION_ERROR_DESCRIPTION"]);
	}
}

%new
- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler
{
	downloadManager.applicationBackgroundSessionCompletionHandler = completionHandler;
}

%new
- (void)sp_applicationWillEnterForeground
{
	if(preferenceManager.forceModeOnResumeEnabled)
	{
		for(BrowserController* controller in browserControllers())
		{
			//Switch mode to specified mode
			[controller modeSwitchAction:preferenceManager.forceModeOnResumeFor];
		}
	}
}

//Auto switch mode on app resume
- (void)applicationWillEnterForeground:(id)arg1 //iOS 12 and down
{
	%orig;
	[self sp_applicationWillEnterForeground];
}

- (void)_applicationWillEnterForeground:(id)arg1 //iOS 13 and up
{
	%orig;
	[self sp_applicationWillEnterForeground];
}

//Auto close tabs when Safari gets closed
- (void)applicationWillTerminate
{
	if(preferenceManager.autoCloseTabsEnabled &&
	   preferenceManager.autoCloseTabsOn == 1 /*Safari closed*/)
	{
		for(BrowserController* controller in browserControllers())
		{
			//Close all tabs for specified modes
			[controller autoCloseAction];
		}
	}

	if(preferenceManager.autoDeleteDataEnabled &&
	   preferenceManager.autoDeleteDataOn == 1 /*Safari closed*/)
	{
		for(BrowserController* controller in browserControllers())
		{
			//Clear browser data
			[controller clearData];
		}
	}

	%orig;
}

%new
- (void)sp_applicationDidEnterBackground
{
	if(preferenceManager.autoCloseTabsEnabled &&
	   preferenceManager.autoCloseTabsOn == 2 /*Safari minimized*/)
	{
		for(BrowserController* controller in browserControllers())
		{
			//Close all tabs for specified modes
			[controller autoCloseAction];
		}
	}

	if(preferenceManager.autoDeleteDataEnabled &&
	   preferenceManager.autoDeleteDataOn == 2 /*Safari closed*/)
	{
		for(BrowserController* controller in browserControllers())
		{
			//Clear browser data
			[controller clearData];
		}
	}
}

//Auto close tabs when Safari gets minimized
- (void)applicationDidEnterBackground:(id)arg1 //iOS 12 and down
{
	[self sp_applicationDidEnterBackground];

	%orig;
}

- (void)_applicationDidEnterBackground:(id)arg1 //iOS 13 and up
{
	[self sp_applicationDidEnterBackground];

	%orig;
}

%group iOS10Up

- (BOOL)canAddNewTabForPrivateBrowsing:(BOOL)privateBrowsing
{
	if(preferenceManager.disableTabLimit)
	{
		return YES;
	}

	return %orig;
}

%end

%group iOS9Up

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
	[self sp_preAppLaunch];

	BOOL orig = %orig;

	[self sp_postAppLaunchWithOptions:launchOptions];

	return orig;
}

%end

%group iOS8

- (void)applicationOpenURL:(NSURL*)URL
{
	if(preferenceManager.forceModeOnExternalLinkEnabled && URL)
	{
		//Switch mode to specified mode
		[browserControllers().firstObject modeSwitchAction:preferenceManager.forceModeOnExternalLinkFor];
	}

	%orig;
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	[self sp_preAppLaunch];

	%orig;

	[self sp_postAppLaunchWithOptions:nil];
}

%end

%end

void initApplication()
{
	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_10_0)
	{
		%init(iOS10Up);
	}

	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_9_0)
	{
		%init(iOS9Up);
	}
	else
	{
		%init(iOS8);
	}

	%init();
}
