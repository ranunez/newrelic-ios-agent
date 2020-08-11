//
//  NRMACrashReport_Symbol.m
//  NewRelicAgent
//
//  Created by Bryce Buchanan on 5/6/14.
//  Copyright (c) 2014 New Relic. All rights reserved.
//

#import "NRMACrashReport_Symbol.h"

@implementation NRMACrashReport_Symbol

- (instancetype) initWithSymbolStartAddr:(NSString*)symbolStartAddr
                              symbolName:(NSString*)symbolName {
    self = [super init];
    if (self) {
        _symbolName = symbolName;
        _symbolStartAddr = symbolStartAddr;
    }
    return self;
}

- (id) JSONObject
{
    /*
     @property(strong) NSString* symbolStartAddr;
     @property(strong) NSString* symbolName;
     */
    NSMutableDictionary* jsonDictionary = [[NSMutableDictionary alloc] init];
    [jsonDictionary setObject:self.symbolStartAddr?:[NSNull null] forKey:kNRMA_CR_symbolStartAddrKey];
    [jsonDictionary setObject:self.symbolName?:[NSNull null] forKey:kNRMA_CR_symbolNameKey];
    return jsonDictionary;
}

@end