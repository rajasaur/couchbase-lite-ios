//
//  CBLView+REST.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/7/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLView+REST.h"
#import "CBLView+Internal.h"
#import "CBLDatabase+REST.h"
#import "CBJSONEncoder.h"


@implementation CBLView (REST)


- (CBLStatus) compileFromDesignDoc {
    if (!self.isDesignDoc && self.registeredMapBlock) /* Native design doc like view */
        return kCBLStatusOK;
    
    // see if there's a design doc with a CouchDB-style view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [self.database getDesignDocFunction: self.name
                                                                                    key: @"views"
                                                                               language: &language]);
    if (!viewProps)
        return kCBLStatusNotFound;
    
    LogTo(View, @"%@: Attempting to compile %@ from design doc", self.name, language);
    if (![CBLView compiler])
        return kCBLStatusNotImplemented;
    return [self compileFromProperties: viewProps language: language];
}


- (CBLStatus) compileFromProperties: (NSDictionary*)viewProps language: (NSString*)language {
    // Version string is based on a digest of the properties:
    NSError* error;
    NSString* version = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: viewProps error: &error]);
    if (!version)
        Warn(@"View %@ could not generate version string from the view properties: %@", self, error);
    
    if ([version isEqualToString: self.mapVersion])
        return kCBLStatusOK; // Same as the current version
    
    if (!language)
        language = @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return kCBLStatusNotFound;
    CBLMapBlock mapBlock = [[CBLView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ could not compile %@ map fn: %@", self.name, language, mapSource);
        return kCBLStatusCallbackError;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    CBLReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock = [[CBLView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ could not compile %@ map fn: %@", self.name, language, reduceSource);
            return kCBLStatusCallbackError;
        }
    }
    
    [self setMapBlock: mapBlock reduceBlock: reduceBlock version: version];

    self.documentType = $castIf(NSString, viewProps[@"documentType"]);
    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    self.collation = ($equal(options[@"collation"], @"raw")) ? kCBLViewCollationRaw
                                                             : kCBLViewCollationUnicode;
    
    // Mark as a design doc view:
    self.isDesignDoc = YES;
    
    return kCBLStatusOK;
}


@end
