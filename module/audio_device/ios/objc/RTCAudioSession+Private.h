
#import "RTCAudioSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface RTCAudioSession ()

/** The lock that guards access to AVAudioSession methods. */
@property(nonatomic, strong) NSRecursiveLock *lock;

/** The delegates. */
@property(nonatomic, readonly) NSSet *delegates;

/** Number of times setActive:YES has succeeded without a balanced call to
 *  setActive:NO.
 */
@property(nonatomic, readonly) NSInteger activationCount;

@end

NS_ASSUME_NONNULL_END
