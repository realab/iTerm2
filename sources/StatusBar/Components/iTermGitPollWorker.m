//
//  iTermGitPollWorker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPollWorker.h"

#import "DebugLogging.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermCommandRunnerPool.h"
#import "iTermGitState+MainApp.h"
#import "iTermSlowOperationGateway.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iTermGitPollWorkerCompletionBlock)(iTermGitState * _Nullable, BOOL timedOut);

@implementation iTermGitPollWorker {
    NSMutableDictionary<NSString *, iTermGitState *> *_cache;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGitPollWorkerCompletionBlock> *> *_pending;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)cachedBranchForPath:(NSString *)path {
    return _cache[path].branch;
}

- (NSString *)debugInfoForDirectory:(NSString *)path {
    iTermGitState *existing = _cache[path];
    NSMutableArray<iTermGitPollWorkerCompletionBlock> *pending = _pending[path];
    return [NSString stringWithFormat:@"Cache status: %@\nPending calls: %@\n",
            existing ? [NSString stringWithFormat:@"Have cached value of age %@", @(existing.age)] : @"No cached value",
            @(pending.count)];
}

- (void)requestPath:(NSString *)path completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion {
    DLog(@"requestPath:%@", path);
    const NSTimeInterval ttl = 1;

    iTermGitState *existing = _cache[path];
    DLog(@"Existing state %@ has age %@", existing, @(existing.age));
    if (existing != nil && existing.age < ttl) {
        completion(existing, NO);
        return;
    }

    NSMutableArray<iTermGitPollWorkerCompletionBlock> *pending = _pending[path];
    if (pending.count) {
        DLog(@"Add to pending request for %@ with %@ waiting blocks. Pending is now:\n%@", path, @(pending.count), _pending);
        [pending addObject:[completion copy]];
        return;
    }

    _pending[path] = [@[ [completion copy] ] mutableCopy];
    DLog(@"Create pending request for %@ with a single waiter", path);
    DLog(@"Send through gateway with the following pending requests:\n%@", _pending);
    [[iTermSlowOperationGateway sharedInstance] requestGitStateForPath:path completion:^(iTermGitState * _Nullable state, BOOL timedOut) {
        DLog(@"Got response for %@ with state %@ timedOut=%@", path, state, @(timedOut));
        [self didFetchState:state timedOut:timedOut path:path];
    }];
}

- (void)didFetchState:(iTermGitState *)state timedOut:(BOOL)timedOut path:(NSString *)path {
    DLog(@"Did fetch state %@ timedOut=%@ for path %@", state, @(timedOut), path);
    iTermGitState *cached = _cache[path];
    if (cached != nil &&
        !isnan(cached.creationTime) &&  // just paranoia to avoid unbounded recursion
        cached.creationTime > state.creationTime) {
        DLog(@"Cached entry is newer. Recurse.");
        // A stale cached state is preferable to a nil reply, but preserve the timeout signal so
        // callers can distinguish "we have no info" from "we have stale info because of a timeout".
        [self didFetchState:cached timedOut:timedOut path:path];
        return;
    }

    DLog(@"Save to cache");
    _cache[path] = state;

    NSArray<iTermGitPollWorkerCompletionBlock> *blocks = _pending[path];
    DLog(@"Invoke %@ blocks", @(blocks.count));
    [_pending removeObjectForKey:path];
    DLog(@"Remove all waiters from pending for %@. Pending is now\n%@", path, _pending);
    [blocks enumerateObjectsUsingBlock:^(iTermGitPollWorkerCompletionBlock  _Nonnull block, NSUInteger idx, BOOL * _Nonnull stop) {
        DLog(@"Invoke completion block for path %@ with state %@ timedOut=%@", path, state, @(timedOut));
        block(state, timedOut);
    }];
}

- (void)invalidateCacheForPath:(NSString *)path {
    [_pending removeObjectForKey:path];
}

@end

NS_ASSUME_NONNULL_END
