//
//  NRLogger.m
//  NewRelicAgent
//
//  Created by Jonathan Karon on 10/9/12.
//  Copyright © 2023 New Relic. All rights reserved.
//

#import "NRLogger.h"
#import "NewRelicInternalUtils.h"
#import "NRMAJSON.h"
#import "NewRelicAgentInternal.h"
#import "NRMAHarvestController.h"
#import "NRMAHarvesterConfiguration.h"
#import "NRMASupportMetricHelper.h"

NRLogger *_nr_logger = nil;

#define kNRMAMaxLogUploadRetry 3

@interface NRLogger()
- (void)addLogMessage:(NSDictionary *)message;
- (void)setLogLevels:(unsigned int)levels;
- (void)setRemoteLogLevel:(unsigned int)level;

- (void)setLogTargets:(unsigned int)targets;
- (void)clearLog;
@end

@implementation NRLogger

+ (NRLogger *)logger {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _nr_logger = [[NRLogger alloc] init];
    });
    return _nr_logger;
}

+ (void)log:(unsigned int)level
     inFile:(NSString *)file
     atLine:(unsigned int)line
   inMethod:(NSString *)method
withMessage:(NSString *)message {
    
    NRLogger *logger = [NRLogger logger];
    BOOL shouldLog = NO;
    
    // This shouldLog BOOL was previously set within a @synchronized block but I was seeing a deadlock. Trying some tests without
    // @synchronized(logger) {
    shouldLog = (logger->logLevels & level) != 0;
    // }
    
    if (shouldLog) {
        [logger addLogMessage:[NSDictionary dictionaryWithObjectsAndKeys:
                               [self levelToString:level], NRLogMessageLevelKey,
                               file, NRLogMessageFileKey,
                               [NSNumber numberWithUnsignedInt:line], NRLogMessageLineNumberKey,
                               method, NRLogMessageMethodKey,
                               [NSNumber numberWithLongLong: (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)], NRLogMessageTimestampKey,
                               message, NRLogMessageMessageKey,
                               nil]: NO];
    }
}

+ (void)log:(unsigned int)level
     inFile:(NSString *)file
     atLine:(unsigned int)line
   inMethod:(NSString *)method
withMessage:(NSString *)message
withAttributes:(NSDictionary *)attributes {
    
    NRLogger *logger = [NRLogger logger];
    BOOL shouldLog = NO;
    
    // This shouldLog BOOL was previously set within a @synchronized block but I was seeing a deadlock. Trying some tests without
    // @synchronized(logger) {
    shouldLog = (logger->logLevels & level) != 0;
    // }
    
    if (shouldLog) {
        NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            [self levelToString:level], NRLogMessageLevelKey,
                                            file, NRLogMessageFileKey,
                                            [NSNumber numberWithUnsignedInt:line], NRLogMessageLineNumberKey,
                                            method, NRLogMessageMethodKey,
                                            [NSNumber numberWithLongLong: (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)], NRLogMessageTimestampKey,
                                            message, NRLogMessageMessageKey,nil];
        [mutableDict addEntriesFromDictionary:attributes];
        [logger addLogMessage:mutableDict:NO];
    }
}

+ (void)log:(unsigned int)level
     inFile:(NSString *)file
     atLine:(unsigned int)line
   inMethod:(NSString *)method
withMessage:(NSString *)message
withAgentLogsOn:(BOOL)agentLogsOn {

    NRLogger *logger = [NRLogger logger];
    BOOL shouldLog = NO;

    // Filter passed logs by log level.
    shouldLog = (logger->logLevels & level) != 0;
  
// Filtering of Console logs is performed based on logLevel.
//    // If this is an agentLog, only print it if we are currently including the debug level.
//    if (agentLogsOn) {
//        shouldLog = (logger->logLevels & NRLogLevelDebug) != 0;
//    }

    if (shouldLog) {
        [logger addLogMessage:[NSDictionary dictionaryWithObjectsAndKeys:
                               [self levelToString:level], NRLogMessageLevelKey,
                               file, NRLogMessageFileKey,
                               [NSNumber numberWithUnsignedInt:line], NRLogMessageLineNumberKey,
                               method, NRLogMessageMethodKey,
                               [NSNumber numberWithLongLong: (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)], NRLogMessageTimestampKey,
                               message, NRLogMessageMessageKey,
                               nil]:agentLogsOn];
    }
}

+ (NRLogLevels) logLevels {
    return [[NRLogger logger] logLevels];
}

+ (void)setLogLevels:(unsigned int)levels {
    [[NRLogger logger] setLogLevels:levels];
}

+ (void)setRemoteLogLevel:(unsigned int)level {
    [[NRLogger logger] setRemoteLogLevel:level];
}

+ (void)setLogTargets:(unsigned int)targets {
    [[NRLogger logger] setLogTargets:targets];
}

+ (void)setLogIngestKey:(NSString*)key {
    [[NRLogger logger] setLogIngestKey:key];
}

+ (void)setLogEntityGuid:(NSString*)key {
    [[NRLogger logger] setLogEntityGuid:key];
}

+ (void)setLogURL:(NSString*) url {
    [[NRLogger logger] setLogURL:url];
}

+ (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    if (basePath) {
        return [[basePath stringByAppendingPathComponent:@"newrelic"] stringByAppendingPathComponent:@"log.json"];
    }
    NSLog(@"NewRelic: No NSDocumentDirectory found, file logging will not be available.");
    return nil;
}

+ (void)clearLog {
    [[NRLogger logger] clearLog];
}

+ (void)enqueueLogUpload {
    [[NRLogger logger] enqueueLogUpload];
}

+ (NRLogLevels)stringToLevel:(NSString*)string {
    if ([ string isEqualToString:@"ERROR"]) {
        return NRLogLevelError;
    }
    else if ([string isEqualToString:@"WARN"]) {
        return NRLogLevelWarning;
    }
    else if ([string isEqualToString:@"INFO"]) {
        return NRLogLevelInfo;
    }
    else if ([string isEqualToString:@"VERBOSE"]) {
        return NRLogLevelVerbose;
    }
    else if ([string isEqualToString:@"AUDIT"]) {
        return NRLogLevelAudit;
    }
    else if ([string isEqualToString:@"DEBUG"]) {
        return NRLogLevelDebug;
    }
    return NRLogLevelError;
}

+ (NSString*)levelToString:(NRLogLevels)level {
    
    if (level ==  NRLogLevelError) {
        return @"ERROR";
    }
    else if (level ==  NRLogLevelWarning) {
        return @"WARN";
    }
    else if (level ==  NRLogLevelInfo) {
        return @"INFO";
    }
    else if (level ==  NRLogLevelVerbose) {
        return @"VERBOSE";
    }
    else if (level ==  NRLogLevelAudit) {
        return @"AUDIT";
    }
    else if (level ==  NRLogLevelDebug) {
        return @"DEBUG";
    }
    return @"ERROR";
}

#pragma mark -- internal

- (id)init {
    self = [super init];
    if (self) {
        
        self->uploadQueue = [NSMutableArray array];
        self->isUploading = NO;
        self->failureCount = 0;
        self->debugLogs = NO;
        self->remoteLogLevel = NRLogLevelError | NRLogLevelWarning;
        // This was including Error and warning previously but since warning is the highest we want to emit by default this will emit warning and error by default.
        
        self->logLevels = NRLogLevelError | NRLogLevelWarning;
        self->logTargets = NRLogTargetConsole;
        self->logFile = nil;
        self->logQueue = dispatch_queue_create("com.newrelicagent.loggingfilequeue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    @synchronized(self) {
        if (self->logFile) {
            [self->logFile closeFile];
            self->logFile = nil;
        }
    }
}

- (void)addLogMessage:(NSDictionary *)message : (BOOL) agentLogsOn {
    // The static method checks the log level before we get here.
    dispatch_async(logQueue, ^{
        if (self->logTargets & NRLogTargetConsole) {
            NSLog(@"NewRelic(%@,%p):\t%@:%@\t%@\n\t%@",
                  [NewRelicInternalUtils agentVersion],
                  [NSThread currentThread],
                  [message objectForKey:NRLogMessageFileKey],
                  [message objectForKey:NRLogMessageLineNumberKey],
                  [message objectForKey:NRLogMessageMethodKey],
                  [message objectForKey:NRLogMessageMessageKey]);
            
        }
        // Only enter this block if remote logging is including this messages level.
        NSString *levelString = [message objectForKey:NRLogMessageLevelKey];
        NRLogLevels level = [NRLogger stringToLevel:levelString];

        BOOL shouldRemoteLog = (self->remoteLogLevel & level) != 0;

        if (agentLogsOn) {
            shouldRemoteLog = (self->remoteLogLevel & NRLogLevelDebug) != 0;
        }

        if ((self->logTargets & NRLogTargetFile) &&
            shouldRemoteLog) {
            @synchronized(self) {
                
                NSData *json = [self jsonDictionary:message];
                if (json) {
                    if ([self->logFile offsetInFile]) {
                        [self->logFile writeData:[NSData dataWithBytes:"," length:1]];
                    }
                    [self->logFile writeData:json];
                    
                    NSFileHandle *handleForReadingAtPath = [NSFileHandle fileHandleForReadingAtPath:[NRLogger logFilePath]];
                    self->lastFileSize = [handleForReadingAtPath seekToEndOfFile];
                    // NSLog(@"logs fileSize = %llu", self->lastFileSize);
                    
                    if (self->lastFileSize > (kNRMAMaxLogPayloadSizeLimit)) {
                        // NSLog(@"logs fileSize exceeds kNRMAMaxLogPayloadSizeLimit , split logs and enqueue upload task");
                        
                        [self enqueueLogUpload];
                    }
                    [handleForReadingAtPath closeFile];
                }
            }
        }
    });
}

- (NSData*) jsonDictionary:(NSDictionary*)message {
    NSString* NRSessionId = [[[NewRelicAgentInternal sharedInstance] currentSessionId] copy];
    NRMAHarvesterConfiguration *configuration = [NRMAHarvestController configuration];

    NSString* nrAppId = [NSString stringWithFormat:@"%lld", configuration.application_id];
    NSString* entityGuid = [NSString stringWithFormat:@"%@", configuration.entity_guid];

    if (!configuration) {
        nrAppId = nil;
        entityGuid = nil;
    }

    if ([entityGuid length] == 0) {
        if (logEntityGuid != nil) {
            entityGuid = logEntityGuid;
        }
    }
    if (!nrAppId) {
        nrAppId = @"";
    }
    if (!NRSessionId) {
        NRSessionId = @"";
    }
    if (!entityGuid) {
        entityGuid = @"";
    }
    // TODO: LogReporting logAttributes: Refactor to construct 9 required attributes and tack on the remaining API provided attributes.

    NSDictionary *requiredAttributes = @{NRLogMessageLevelKey:      [message objectForKey:NRLogMessageLevelKey],                                                                 // 1
                                         NRLogMessageFileKey:       [[message objectForKey:NRLogMessageFileKey]stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],   // 2
                                         NRLogMessageLineNumberKey: [message objectForKey:NRLogMessageLineNumberKey],                                                            // 3
                                         NRLogMessageMethodKey:     [[message objectForKey:NRLogMessageMethodKey]stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""], // 4
                                         NRLogMessageTimestampKey:  [message objectForKey:NRLogMessageTimestampKey],                                                             // 5
                                         NRLogMessageMessageKey:    [[message objectForKey:NRLogMessageMessageKey]stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],// 6
                                         @"sessionId": NRSessionId,                                                                                                              // 7
                                         @"appId": nrAppId,                                                                                                                      // 8
                                         @"entity.guid": entityGuid};                                                                                                            // 9

    NSMutableDictionary *providedAttributes = [message mutableCopy];
    [providedAttributes removeObjectsForKeys:@[NRLogMessageLevelKey,NRLogMessageFileKey,NRLogMessageLineNumberKey,NRLogMessageMethodKey,NRLogMessageTimestampKey,NRLogMessageMessageKey]];
    [providedAttributes addEntriesFromDictionary:requiredAttributes];
    NSError* error = nil;

    NSData *logJsonData = [NRMAJSON dataWithJSONObject:providedAttributes
                                                 options:0
                                                   error:&error];
    
    return logJsonData;
}

- (void)setLogLevels:(unsigned int)levels {
    @synchronized(self) {
        unsigned int l = 0;
        switch (levels) {
            case NRLogLevelError:
                l = NRLogLevelError; break;
            case NRLogLevelWarning:
                l = NRLogLevelError | NRLogLevelWarning; break;
            case NRLogLevelInfo:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo; break;
            case NRLogLevelVerbose:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose; break;
            case NRLogLevelAudit:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose | NRLogLevelAudit ; break;
            case NRLogLevelDebug:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose | NRLogLevelAudit | NRLogLevelDebug ; break;
            default:
                l = levels; break;
        }
        self->logLevels = l;
    }
}

- (void)setRemoteLogLevel:(unsigned int)level {
    @synchronized(self) {
        unsigned int l = 0;
        switch (level) {
            case NRLogLevelError:
                l = NRLogLevelError; break;
            case NRLogLevelWarning:
                l = NRLogLevelError | NRLogLevelWarning; break;
            case NRLogLevelInfo:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo; break;
            case NRLogLevelVerbose:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose; break;
            case NRLogLevelAudit:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose | NRLogLevelAudit ; break;
            case NRLogLevelDebug:
                l = NRLogLevelError | NRLogLevelWarning | NRLogLevelInfo | NRLogLevelVerbose | NRLogLevelAudit | NRLogLevelDebug ; break;
            default:
                l = level; break;
        }

        self->remoteLogLevel = l;
    }
}

- (NRLogLevels) logLevels {
    return self->logLevels;
}

- (void)setLogTargets:(unsigned int)targets {
    NSString *fileOpenError = nil;
    
    @synchronized(self) {
        self->logTargets = targets;
        if (targets & NRLogTargetFile) {
            if (! self->logFile) {
                NSString *path = [NRLogger logFilePath];
                NSString *parent = [path stringByDeletingLastPathComponent];
                NSError *err;
                BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:parent
                                                         withIntermediateDirectories:YES
                                                                          attributes:nil
                                                                               error:&err];
                if (! success) {
                    fileOpenError = [NSString stringWithFormat:@"Cannot create log file directory '%@': %@", parent, [err description]];
                }
                else {
                    if (! [[NSFileManager defaultManager] fileExistsAtPath:path]) {
                        success = [[NSFileManager defaultManager] createFileAtPath:path
                                                                          contents:[[NSData alloc] init]
                                                                        attributes:nil];
                        if (! success) {
                            fileOpenError = [NSString stringWithFormat:@"Cannot create log file '%@'", path];
                        }
                    }
                    if (success) {
                        self->logFile = [NSFileHandle fileHandleForUpdatingAtPath:path];
                        [self->logFile seekToEndOfFile];
                        if (! self->logFile) {
                            success = NO;
                            fileOpenError = [NSString stringWithFormat:@"Cannot write log file '%@'", path];
                        }
                    }
                }
                
                if (! success) {
                    self->logTargets &= ~NRLogTargetFile;
                }
            }
        }
        else {
            if (self->logFile) {
                [self->logFile closeFile];
                self->logFile = nil;
            }
        }
    }
    
    if (fileOpenError) {
        if (self->logTargets && self->logLevels) {
            NRLOG_AGENT_ERROR(@"%@", fileOpenError);
        }
        else {
            NSLog(@"NewRelic: error opening log file %@", fileOpenError);
        }
    }
}

- (void)clearLog {
    @synchronized(self) {
        if (self->logFile) {
            // Close the log file if it's open.
            self->lastFileSize = 0;
            
            [self->logFile closeFile];
            self->logFile = nil;
            
            // Truncate the log file on disk.
            NSString *path = [NRLogger logFilePath];
            NSError *err = nil;
            if (! [[NSFileManager defaultManager] removeItemAtPath:path error:&err]) {
                NSLog(@"NewRelic: Unable to truncate log file at '%@'", path);
            }
            
            // Calling setLogTargets: will re-open the file safely.
            // Note: @synchronized is re-entrant, so we don't need to worry about lock contention.
            [self setLogTargets:self->logTargets];
        }
    }
}

- (void)setLogIngestKey:(NSString*)url {
    self->logIngestKey = url;
}

- (void)setLogEntityGuid:(NSString*)url {
    self->logEntityGuid = url;
}

- (void)setLogURL:(NSString*)url {
    self->logURL = url;
}

//  Enqueue an upload task for this specific logData , represented by the "formattedData" below.
- (void)enqueueLogUpload {
    @synchronized(self) {
        if (self->logFile) {
            
            if (debugLogs) {
                NSLog(@"Logs enqueueLogUpload called..");
            }
            NSString *path = [NRLogger logFilePath];
            NSData* logData = [NSData dataWithContentsOfFile:path];
            
            if (logData == nil) {
                return;
            }
            if ([logData length] == 0) {
                return;
            }

            NSString* logMessagesJson = [NSString stringWithFormat:@"[ %@ ]", [[NSString alloc] initWithData:logData encoding:NSUTF8StringEncoding]];
            NSData* formattedData = [logMessagesJson dataUsingEncoding:NSUTF8StringEncoding];
            
            // We clear the log when we save the existing logs to uploadQueue.
            [self clearLog];
            
            // Save formatted Data as an upload at the end of the upload queue.
            [self->uploadQueue addObject:formattedData];
            
            [self processNextUploadTask];
        }
        else {
            NSLog(@"Logs upload failed due to missing logFile. failing.");
        }
    }
}

// Perform upload task for specific logData, saved into uploadQueue previously.
- (void) processNextUploadTask {
    dispatch_async(logQueue, ^{
        // If we are already uploading, or we've reached the end of the upload queue, do nothing.
        if (self->isUploading || self->uploadQueue.count == 0) {
            return;
        }
        
        // Logs cannot be uploaded if we don't have ingest key and logURL set, exit if thats the case.
        if (!self->logIngestKey || !self->logURL) {
            NRLOG_AGENT_ERROR(@"Attempted to upload logs without log ingest key or logURL set. Failing.");
            return;
        }
        
        self->isUploading = YES;
        
        if (self->debugLogs) {
            NSLog(@"Logs isUploading ==> TRUE");
        }
        NSData *formattedData = [self->uploadQueue firstObject];
        
        if (self->debugLogs) {
            //NSString* logMessagesJson = [NSString stringWithFormat:@"[ %@ ]", [[NSString alloc] initWithData:formattedData encoding:NSUTF8StringEncoding]];
            NSArray* decode = [NSJSONSerialization JSONObjectWithData:formattedData
                                                                   options:0
                                                                     error:nil];
            NSLog(@"Uploading log data:\n %@", decode);
        }

        NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSession.sharedSession.configuration];
        NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString: self->logURL]];
        [req setValue:self->logIngestKey forHTTPHeaderField:@"X-App-License-Key"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

        req.HTTPMethod = @"POST";
        
        NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:req fromData:formattedData completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            BOOL errorCode = false;
            NSInteger errorCodeInt = 0;
            
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                errorCode = ((NSHTTPURLResponse*)response).statusCode >= 300;
                errorCodeInt = ((NSHTTPURLResponse*)response).statusCode;
            }
            if (!error && !errorCode) {
                NRLOG_AGENT_VERBOSE(@"Logs uploaded successfully.");
                // Remove the first element from the upload queue.
                [self->uploadQueue removeObjectAtIndex:0];
                self->failureCount = 0;
                
                [NRMASupportMetricHelper enqueueLogSuccessMetric: [formattedData length]];
            }
            else if (errorCode) {
                NRLOG_AGENT_ERROR(@"Logs failed to upload. response: %@", response);
                self->failureCount = self->failureCount + 1;
                
                [NRMASupportMetricHelper enqueueLogFailedMetric];
            }
            else {
                NRLOG_AGENT_ERROR(@"Logs failed to upload. error: %@", error);
                self->failureCount = self->failureCount + 1;
                
                // send log payload failed support metric
                [NRMASupportMetricHelper enqueueLogFailedMetric];
            }
            
            if (self->failureCount > kNRMAMaxLogUploadRetry) {
                [self->uploadQueue removeObjectAtIndex:0];
                self->failureCount = 0;
            }
            
            // isUploading is turned off upon successful or failed logs request.
            self->isUploading = NO;
            
            if (self->debugLogs) {
                NSLog(@"isUploading ==> FALSE");
                if (self->uploadQueue.count > 0) {
                    NSLog(@"logs uploadQueue has contents, proceeding with additional uploads");
                }
                for (NSData *data in self->uploadQueue) {
                    NSLog(@"logs item: length=%lu",(unsigned long)data.length);
                }
                NSLog(@"Logs isUploading ==> FALSE");
            }
            
            [self processNextUploadTask];
        }];
        
        [uploadTask resume];
    });
}

@end

