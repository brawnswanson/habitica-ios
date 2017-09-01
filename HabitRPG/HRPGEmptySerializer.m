//
//  HRPGLoginData.h
//  HabitRPG
//
//  Created by Phillip Thelen on 16/03/14.
//  Copyright © 2017 HabitRPG Inc. All rights reserved.
//

#import "HRPGEmptySerializer.h"

@implementation HRPGEmptySerializer

+ (id)objectFromData:(NSData *)data error:(NSError **)error {
    NSLog(@"Using empty serializer");
    return @"";
}

+ (NSData *)dataFromObject:(id)object error:(NSError **)error {
    NSLog(@"Using empty serializer");
    return nil;
}

@end
