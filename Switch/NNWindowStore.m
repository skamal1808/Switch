//
//  NNWindowStore.m
//  Switch
//
//  Created by Scott Perry on 02/22/13.
//  Copyright © 2013 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "NNWindowStore.h"

#import "NNApplication+Private.h"
#import "NNWindow+Private.h"
#import "NNWindowListWorker.h"
#import "NNWindowWorker.h"


@interface NNWindowStore ()

@property (nonatomic, strong) id<NNWindowStoreDelegate> delegate;
@property (nonatomic, assign) BOOL firstUpdate;

// Serialization
@property (nonatomic, strong) dispatch_queue_t lock;

// Window list updates
@property (nonatomic, strong) NNWindowListWorker *listWorker;
@property (nonatomic, strong) NSArray *windows;

// Window content updates
@property (nonatomic, assign) BOOL updatingWindowContents;
@property (nonatomic, strong) NSMutableDictionary *windowWorkers;

@end


@implementation NNWindowStore

- (instancetype)initWithDelegate:(id<NNWindowStoreDelegate>)delegate;
{
    if (!(self = [super init])) { return nil; }
    
    _delegate = (id<NNWindowStoreDelegate>)[NNDelegateProxy proxyWithDelegate:delegate protocol:@protocol(NNWindowStoreDelegate)];
    _windows = [NSArray new];
    _firstUpdate = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pollCompleteNotification:) name:[[NNWindowListWorker class] notificationName] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pollCompleteNotification:) name:[[NNWindowWorker class] notificationName] object:nil];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:[[NNWindowListWorker class] notificationName] object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:[[NNWindowWorker class] notificationName] object:nil];
}

#pragma mark Actions

- (void)startUpdatingWindowList;
{
    NNAssertMainQueue();

    self.firstUpdate = YES;

    if (!self.listWorker) {
        self.listWorker = [NNWindowListWorker new];
    }
}

- (void)stopUpdatingWindowList;
{
    NNAssertMainQueue();

    self.listWorker = nil;
    [self listWorker:nil didUpdateWindowList:@[]];
}

- (void)startUpdatingWindowContents;
{
    NNAssertMainQueue();

    self.updatingWindowContents = YES;
    self.windowWorkers = [NSMutableDictionary dictionaryWithCapacity:[_windows count]];
    for (NNWindow *window in _windows) {
        NNWindowWorker *worker = [[NNWindowWorker alloc] initWithModelObject:window];
        [self.windowWorkers setObject:worker forKey:window];
    }
}

- (void)stopUpdatingWindowContents;
{
    NNAssertMainQueue();
    
    self.updatingWindowContents = NO;
    self.windowWorkers = nil;
}

#pragma mark Notifications

- (void)pollCompleteNotification:(NSNotification *)note;
{
    if ([note.object isKindOfClass:[NNWindowListWorker class]]) {
        [self listWorker:note.object didUpdateWindowList:note.userInfo[@"windows"]];
    } else if ([note.object isKindOfClass:[NNWindowWorker class]]) {
        [self windowWorker:note.object didUpdateContentsOfWindow:note.userInfo[@"window"]];
    }
}

- (oneway void)windowWorker:(NNWindowWorker *)worker didUpdateContentsOfWindow:(NNWindow *)window;
{
    
    if ([self.windows containsObject:window]) {
        id<NNWindowStoreDelegate> delegate = self.delegate;
        [delegate storeWillChangeContent:self];
        [delegate store:self didChangeWindow:window atIndex:[self.windows indexOfObject:window] forChangeType:NNWindowStoreChangeWindowContent newIndex:[self.windows indexOfObject:window]];
        [delegate storeDidChangeContent:self];
    }
}

- (void)listWorker:(NNWindowListWorker *)worker didUpdateWindowList:(NSArray *)newArray;
{
    if (worker != self.listWorker) { return; }
    
    NSMutableArray *oldArray = [NSMutableArray arrayWithArray:_windows];
    
    BOOL windowsChanged = ![oldArray isEqualToArray:newArray];
    __strong __typeof__(self.delegate) delegate = self.delegate;
    
    if (windowsChanged || self.firstUpdate) {
        [delegate storeWillChangeContent:self];
    }
    
    NSMutableArray *changes = [NSMutableArray new];
    for (int i = (int)[oldArray count] - 1; i >= 0; --i) {
        NNWindow *window = oldArray[(NSUInteger)i];
        
        if (![newArray containsObject:window]) {
            [delegate store:self didChangeWindow:window atIndex:[oldArray indexOfObject:window] forChangeType:NNWindowStoreChangeDelete newIndex:NSNotFound];
            
            [changes addObject:window];
            
            if (self.updatingWindowContents) {
                [self.windowWorkers removeObjectForKey:window];
            }
        }
    }
    // Match old array with new.
    [oldArray removeObjectsInArray:changes];
    [changes removeAllObjects];

    for (NNWindow *window in newArray) {
        if (![oldArray containsObject:window]) {
            [delegate store:self didChangeWindow:window atIndex:NSNotFound forChangeType:NNWindowStoreChangeInsert newIndex:[newArray indexOfObject:window]];
            
            // Match old array with new.
            [oldArray insertObject:window atIndex:[newArray indexOfObject:window]];
            
            if (self.updatingWindowContents) {
                NNWindowWorker *windowWorker = [[NNWindowWorker alloc] initWithModelObject:window];
                [self.windowWorkers setObject:windowWorker forKey:window];
            }
        }
    }
    
    for (NNWindow *window in newArray) {
        NSUInteger oldIndex = [oldArray indexOfObject:window];
        NSUInteger newIndex = [newArray indexOfObject:window];

        if (oldIndex != newIndex) {
            [delegate store:self didChangeWindow:window atIndex:oldIndex forChangeType:NNWindowStoreChangeMove newIndex:newIndex];

            [oldArray removeObjectAtIndex:oldIndex];
            [oldArray insertObject:window atIndex:[newArray indexOfObject:window]];
        }
    }
    
    if (windowsChanged || self.firstUpdate) {
        _windows = newArray;
        
        [delegate storeDidChangeContent:self];
        
        self.firstUpdate = NO;
    }
}

@end
