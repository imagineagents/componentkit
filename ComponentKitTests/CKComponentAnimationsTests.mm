/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <XCTest/XCTest.h>

#import <ComponentKit/CKCasting.h>
#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKComponentScopeRootFactory.h>
#import <ComponentKit/CKComponentSubclass.h>
#import <ComponentKit/CKComponentAnimations.h>
#import <ComponentKit/CKCompositeComponentInternal.h>
#import <ComponentKit/CKThreadLocalComponentScope.h>

#import "CKComponentAnimationsEquality.h"

@interface CKComponentAnimationsTests_Diffing : XCTestCase
@end

@interface ComponentWithScope: CKCompositeComponent
@end

@interface ComponentWithInitialMountAnimations: CKComponent
+ (instancetype)newWithInitialMountAnimations:(std::vector<CKComponentAnimation>)animations;
@end

@interface ComponentWithAnimationsFromPreviousComponent: CKComponent
+ (instancetype)newWithAnimations:(std::vector<CKComponentAnimation>)animations
            fromPreviousComponent:(CKComponent *const)component;
@end

@implementation CKComponentAnimationsTests_Diffing

- (void)test_WhenPreviousTreeIsEmpty_ReturnsAllComponentsWithInitialMountAnimationsAsAppeared
{
  const auto r = CKComponentScopeRootWithDefaultPredicates(nil, nil, YES);
  const auto bcr = CKBuildComponent(r, {}, ^{
    return [ComponentWithScope newWithComponent:[ComponentWithInitialMountAnimations new]];
  });
  const auto c = CK::objCForceCast<ComponentWithScope>(bcr.component);

  const auto diff = CK::animatedComponentsBetweenScopeRoots(bcr.scopeRoot, r);

  const auto expectedDiff = CK::ComponentTreeDiff {
    .appearedComponents = {c.component},
  };
  XCTAssert(diff == expectedDiff);
}

- (void)test_WhenPreviousTreeIsNotEmpty_ReturnsOnlyNewComponentsWithInitialMountAnimationsAsAppeared
{
  const auto bcr = CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil, YES), {}, ^{
    return [ComponentWithScope newWithComponent:[ComponentWithInitialMountAnimations new]];
  });
  const auto bcr2 = CKBuildComponent(bcr.scopeRoot, {}, ^{
    return [ComponentWithScope newWithComponent:[ComponentWithInitialMountAnimations new]];
  });

  const auto diff = CK::animatedComponentsBetweenScopeRoots(bcr2.scopeRoot, bcr.scopeRoot);

  XCTAssert(diff == CK::ComponentTreeDiff {});
}

- (void)test_WhenPreviousTreeIsNotEmpty_ReturnsComponentsWithChangeAnimationsAsUpdated
{
  const auto bcr = CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil, YES), {}, ^{
    return [ComponentWithScope newWithComponent:[ComponentWithAnimationsFromPreviousComponent new]];
  });
  const auto c = CK::objCForceCast<ComponentWithScope>(bcr.component);
  const auto bcr2 = CKBuildComponent(bcr.scopeRoot, {}, ^{
    return [ComponentWithScope newWithComponent:[ComponentWithAnimationsFromPreviousComponent new]];
  });
  const auto c2 = CK::objCForceCast<ComponentWithScope>(bcr2.component);

  const auto diff = CK::animatedComponentsBetweenScopeRoots(bcr2.scopeRoot, bcr.scopeRoot);

  const auto expectedDiff = CK::ComponentTreeDiff {
    .updatedComponents = {{c.component, c2.component}},
  };
  XCTAssert(diff == expectedDiff);
}

@end

@interface CKComponentAnimationsTests: XCTestCase
@end

@implementation CKComponentAnimationsTests

- (void)test_WhenThereAreNoComponentsToAnimate_ThereAreNoAnimations
{
  const auto as = CK::animationsForComponents({});

  const auto expected = CKComponentAnimations::AnimationsByComponentMap {};
  XCTAssert(animationsAreEqual(as.animationsOnInitialMount(), expected));
}

- (void)test_ForAllAppearedComponents_AnimationsOnInitialMountAreCollected
{
  const auto a1 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto c1 = [ComponentWithInitialMountAnimations newWithInitialMountAnimations:{a1}];
  const auto a2 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto c2 = [ComponentWithInitialMountAnimations newWithInitialMountAnimations:{a2}];
  const auto diff = CK::ComponentTreeDiff {
    .appearedComponents = {
      c1,
      c2,
    },
  };

  const auto as = animationsForComponents(diff);

  const auto expected = CKComponentAnimations::AnimationsByComponentMap {
    {c1, {a1}},
    {c2, {a2}},
  };
  XCTAssert(animationsAreEqual(as.animationsOnInitialMount(), expected));
}

- (void)test_ForAllUpdatedComponents_AnimationsFromPreviousComponentAreCollected
{
  const auto a1 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto pc1 = [CKComponent new];
  const auto c1 = [ComponentWithAnimationsFromPreviousComponent newWithAnimations:{a1} fromPreviousComponent:pc1];
  const auto a2 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto pc2 = [CKComponent new];
  const auto c2 = [ComponentWithAnimationsFromPreviousComponent newWithAnimations:{a2} fromPreviousComponent:pc2];
  const auto componentPairs = std::vector<CK::ComponentTreeDiff::Pair> {
    {pc1, c1},
    {pc2, c2},
  };
  const auto diff = CK::ComponentTreeDiff {
    .updatedComponents = componentPairs,
  };

  const auto as = animationsForComponents(diff);

  const auto expected = CKComponentAnimations::AnimationsByComponentMap {
    {c1, {a1}},
    {c2, {a2}},
  };
  XCTAssert(animationsAreEqual(as.animationsFromPreviousComponent(), expected));
}

- (void)test_DefaultInitialised_IsEmpty
{
  XCTAssert(CKComponentAnimations {}.isEmpty());
}

- (void)test_IfHasInitialAnimations_IsNotEmpty
{
  const auto a1 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto c1 = [ComponentWithInitialMountAnimations newWithInitialMountAnimations:{a1}];
  const auto as = CKComponentAnimations {
    {
      {c1, {a1}},
    },
    {}
  };

  XCTAssertFalse(as.isEmpty());
}

- (void)test_IfHasAnimationsFromPreviousComponent_IsNotEmpty
{
  const auto a1 = CKComponentAnimation([CKComponent new], [CAAnimation new]);
  const auto c1 = [ComponentWithInitialMountAnimations newWithInitialMountAnimations:{a1}];
  const auto as = CKComponentAnimations {
    {},
    {
      {c1, {a1}},
    }
  };

  XCTAssertFalse(as.isEmpty());
}

@end

@implementation ComponentWithScope
+ (instancetype)newWithComponent:(CKComponent *)component
{
  CKComponentScope s(self);
  return [super newWithComponent:component];
}
@end

@implementation ComponentWithInitialMountAnimations {
  std::vector<CKComponentAnimation> _animations;
}

+ (instancetype)new
{
  return [self newWithInitialMountAnimations:{}];
}

+ (instancetype)newWithInitialMountAnimations:(std::vector<CKComponentAnimation>)animations
{
  CKComponentScope s(self);
  const auto c = [super new];
  c->_animations = std::move(animations);
  return c;
}

- (std::vector<CKComponentAnimation>)animationsOnInitialMount { return _animations; }
@end

@implementation ComponentWithAnimationsFromPreviousComponent{
  std::vector<CKComponentAnimation> _animations;
  CKComponent *_previousComponent;
}

+ (instancetype)new
{
  return [self newWithAnimations:{} fromPreviousComponent:nil];
}

+ (instancetype)newWithAnimations:(std::vector<CKComponentAnimation>)animations
            fromPreviousComponent:(CKComponent *const)component
{
  CKComponentScope s(self);
  const auto c = [super new];
  c->_animations = std::move(animations);
  c->_previousComponent = component;
  return c;
}

- (std::vector<CKComponentAnimation>)animationsFromPreviousComponent:(CKComponent *)previousComponent
{
  if (previousComponent == _previousComponent) {
    return _animations;
  } else {
    return {};
  };
}
@end
