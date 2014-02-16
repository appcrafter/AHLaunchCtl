//  AHLaunchJob.m
//  Copyright (c) 2014 Eldon Ahrold ( https://github.com/eahrold/AHLaunchCtl )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.



#import "AHLaunchJob.h"
#import <objc/runtime.h>
#import <ServiceManagement/ServiceManagement.h>
NSDictionary * AHJobCopyDictionary(AHLaunchDomain domain, NSString* label);

@interface AHLaunchJob ()
@property (copy,readwrite)  NSMutableDictionary * jdictionary;
@property (nonatomic, readwrite)     AHLaunchDomain  domain;//
@property (nonatomic, readwrite)     NSInteger LastExitStatus;//
@property (nonatomic, readwrite)     NSInteger PID;//
@property (nonatomic, readwrite)     BOOL      isCurrentlyLoaded;//
@end

#pragma mark - AHLaunchJob
@implementation AHLaunchJob{
}

-(instancetype)init{
    self = [super init];
    if(self){
        [self startObservingOnAllProperties];
    }
    return self;
}

-(instancetype)initWithoutObservers{
    self = [super init];
    if(self){
        _jdictionary = [[NSMutableDictionary alloc]initWithCapacity:31];
    }
    return [super init];
}

-(void)dealloc{
    [self removeObservingOnAllProperties];
}

#pragma mark -
-(NSDictionary *)dictionary{
    return [NSDictionary dictionaryWithDictionary:_jdictionary];
}

-(NSSet*)ignoredProperties{
    NSSet* ignoredProperties = [NSSet setWithObjects:@"PID",@"LastExitStatus",@"isCurrentlyLoaded",@"domain", nil];
    return ignoredProperties;
}

#pragma mark - Observing
-(void)startObservingOnAllProperties{
    unsigned int count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    for (int i = 0; i < count; ++i){
        const char *property = property_getName(properties[i]);
        NSString* keyPath = [NSString stringWithUTF8String:property];
        if(![[self ignoredProperties] member:keyPath]){
            [self addObserver:self
                   forKeyPath:keyPath
                      options:NSKeyValueObservingOptionNew
                      context:NULL];
        }
    }
    free(properties);
}
-(void)removeObservingOnAllProperties{
    unsigned int count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    for (int i = 0; i < count; ++i){
        const char *property = property_getName(properties[i]);
        NSString* keyPath = [NSString stringWithUTF8String:property];
        @try {
            if(![[self ignoredProperties] member:keyPath]){
                [self removeObserver:self forKeyPath:keyPath];
            }
        }
        @catch (NSException *exception) {}
    }
    free(properties);
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if(!_jdictionary){
        _jdictionary = [[NSMutableDictionary alloc]initWithCapacity:31];
    }
    
    id chng = change[@"new"];
    objc_property_t property = class_getProperty([self class], keyPath.UTF8String);
    const char *p = property_getAttributes(property);
    
    if(p != NULL){
        if(!strncmp("Tc", p, 2)){
            [self writeBoolValueToDict:chng forKey:keyPath];
        }
        else
            [self writeObjectValueToDict:chng forKey:keyPath];
    }
}

#pragma mark - Accessors
-(NSInteger)LastExitStatus{
    if(_LastExitStatus){
        return _LastExitStatus;
    }
    id value = [self serviceManagementValueForKey:@"LastExitStatus"];
    if(!value || ![value isKindOfClass:[NSNumber class]]){
        return -1;
    }
    return [value integerValue];
}

-(NSInteger)PID{
    if(_PID){
        return _PID;
    }
    id value = [self serviceManagementValueForKey:@"PID"];
    if(!value || ![value isKindOfClass:[NSNumber class]]){
        return -1;
    }
    return [value integerValue];
}

-(BOOL)isCurrentlyLoaded{
    id test = [self serviceManagementValueForKey:@"Label"];
    if(test)return YES;
    return NO;
}

-(NSString *)description{
    if(!_jdictionary.count){
        return @"No Job Set";
    }else{
        NSInteger pid = self.PID;
        NSString* pidStr;
        if(pid == -1){
            pidStr = @"--";
        }else{
            pidStr = [NSString stringWithFormat:@"%ld",pid];
        }
        NSInteger les = self.LastExitStatus;
        NSString *lesStr;
        if(les == -1){
            lesStr = @"--";
        }else{
            lesStr = [NSString stringWithFormat:@"%ld",les];
        }
        NSString* loaded = self.isCurrentlyLoaded ? @"YES":@"NO";

        NSString *format = [NSString stringWithFormat:@"Loaded:%@\t LastExit:%@\t PID:%@\t Label:%@",loaded,lesStr,pidStr,_Label ];
        return format;
    }
}

#pragma mark - Internal Methods
-(id)serviceManagementValueForKey:(NSString*)key{
    if(_Label && _domain != 0){
        NSDictionary* dict =  AHJobCopyDictionary(_domain, _Label);
        return [dict objectForKey:key];
    }else{
        return nil;
    }
}

-(void)writeBoolValueToDict:(id)value forKey:(NSString*)keyPath{
    if([value  isEqual: @YES]){
        [_jdictionary setValue:[NSNumber numberWithBool:(BOOL)value] forKey:keyPath];
    }else{
        [_jdictionary removeObjectForKey:keyPath];
    }
}

-(void)writeObjectValueToDict:(id)value forKey:(NSString *)keyPath{
    NSString* stringValue;
    if([value isKindOfClass:[NSString class]])
        stringValue = value;
    if([value isKindOfClass:[NSNull class]]|| [stringValue isEqualToString:@""]){
        [_jdictionary removeObjectForKey:keyPath];
    }else{
        [_jdictionary setValue:value forKey:keyPath];
    }
}

#pragma mark - Secure Coding
-(id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    NSSet* SAND = [NSSet setWithObjects:[NSArray class],[NSDictionary class],[NSString class],[NSNumber class], nil];
    
    if(self){
        _jdictionary = [aDecoder decodeObjectOfClasses:SAND forKey:@"dictionary"];
        _Label = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"Label"];
        _Program = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"Program"];
        _ProgramArguments = [aDecoder decodeObjectOfClasses:SAND forKey:@"ProgramArguments"];
    }
    return self;
}

+(BOOL)supportsSecureCoding{return YES;}
-(void)encodeWithCoder:(NSCoder *)aEncoder{
    [aEncoder encodeObject:_jdictionary forKey:@"dictionary"];
    [aEncoder encodeObject:_Label forKey:@"Label"];
    [aEncoder encodeObject:_Program forKey:@"Program"];
    [aEncoder encodeObject:_ProgramArguments forKey:@"ProgramArguments"];
}

#pragma mark - Class Methods
+(AHLaunchJob *)jobFromDictionary:(NSDictionary *)dict{
    assert(dict != nil);
    AHLaunchJob* job = [[AHLaunchJob alloc]initWithoutObservers];
    for (id key in dict){
        if([key isKindOfClass:[NSString class]]){
            @try {
                [job setValue:[dict valueForKey:key] forKey:key];
            }
            @catch (NSException *exception) {
                NSLog(@"Exception Raised: %@",exception);
            }
            [job.jdictionary setValue:[dict valueForKey:key] forKey:key];
        }
    }
    [job startObservingOnAllProperties];
    return job;
}

+(AHLaunchJob *)jobFromFile:(NSString *)file{
    NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:file];
    return [self jobFromDictionary:dict];
}

@end
#pragma mark - Functions
const CFStringRef SMDomain(AHLaunchDomain domain){
    if(domain > kAHGlobalLaunchAgent){
        return kSMDomainSystemLaunchd;
    }else{
        return kSMDomainUserLaunchd;
    }
}

NSDictionary * AHJobCopyDictionary(AHLaunchDomain domain, NSString* label){
    NSDictionary *dict;
    if(label && domain != 0){
        dict =  CFBridgingRelease(SMJobCopyDictionary(SMDomain(domain),
                                        (__bridge CFStringRef)(label)));
        return dict;
    }else{
        return nil;
    }
}