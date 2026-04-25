//
//  iTermGitState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitState.h"

NSString *const iTermGitStateVariableNameGitBranch = @"user.gitBranch";
NSString *const iTermGitStateVariableNameGitPushCount = @"user.gitPushCount";
NSString *const iTermGitStateVariableNameGitPullCount = @"user.gitPullCount";
NSString *const iTermGitStateVariableNameGitDirty = @"user.gitDirty";
NSString *const iTermGitStateVariableNameGitAdds = @"user.gitAdds";
NSString *const iTermGitStateVariableNameGitDeletes = @"user.gitDeletes";

NSArray<NSString *> *iTermGitStatePaths(void) {
    return @[ iTermGitStateVariableNameGitBranch,
              iTermGitStateVariableNameGitPushCount,
              iTermGitStateVariableNameGitPullCount,
              iTermGitStateVariableNameGitDirty,
              iTermGitStateVariableNameGitAdds,
              iTermGitStateVariableNameGitDeletes ];
}

@implementation iTermGitState

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.xcode forKey:@"xcode"];
    [coder encodeObject:self.ahead forKey:@"ahead"];
    [coder encodeObject:self.behind forKey:@"behind"];
    [coder encodeObject:self.branch forKey:@"branch"];
    [coder encodeBool:self.dirty forKey:@"dirty"];
    [coder encodeInteger:self.adds forKey:@"adds"];
    [coder encodeInteger:self.deletes forKey:@"deletes"];
    [coder encodeInteger:self.creationTime forKey:@"creationTime"];
    [coder encodeInteger:self.repoState forKey:@"repoState"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _xcode = [coder decodeObjectOfClass:[NSString class] forKey:@"xcode"];
        _ahead = [coder decodeObjectOfClass:[NSString class] forKey:@"ahead"];
        _behind = [coder decodeObjectOfClass:[NSString class] forKey:@"behind"];
        _branch = [coder decodeObjectOfClass:[NSString class] forKey:@"branch"];
        _dirty = [coder decodeBoolForKey:@"dirty"];
        _adds = [coder decodeIntegerForKey:@"adds"];
        _deletes = [coder decodeIntegerForKey:@"deletes"];
        _creationTime = [coder decodeIntegerForKey:@"creationTime"];
        _repoState = [coder decodeIntegerForKey:@"repoState"];
    }
    return self;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermGitState *theCopy = [[iTermGitState alloc] init];
    theCopy.xcode = self.xcode.copy;
    theCopy.ahead = self.ahead.copy;
    theCopy.behind = self.behind.copy;
    theCopy.branch = self.branch.copy;
    theCopy.dirty = self.dirty;
    theCopy.adds = self.adds;
    theCopy.deletes = self.deletes;
    return theCopy;
}

#pragma mark NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dir=%@ xcode=%@ ahead=%@ behind=%@ branch=%@ dirty=%@ adds=%@ deletes=%@>",
            self.class, self,
            _directory, _xcode, _ahead, _behind, _branch, @(_dirty), @(_adds), @(_deletes)];
}

- (NSString *)prettyDescription {
    return [NSString stringWithFormat:@"dir=%@ xcode=%@ ahead=%@ behind=%@ branch=%@ dirty=%@ adds=%@ deletes=%@",
            _directory, _xcode, _ahead, _behind, _branch, @(_dirty), @(_adds), @(_deletes)];

}
@end

