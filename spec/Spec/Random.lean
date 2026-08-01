namespace Spec.Random

opaque State : Type

axiom stateValue : State → Nat

axiom stateExtensionality (left right : State) :
  stateValue left = stateValue right → left = right

opaque stateBits : Nat

axiom stateBitsValue : stateBits = 48

opaque modulus : Nat

axiom modulusValue : modulus = 281474976710656

axiom modulusAsPower : modulus = 2 ^ stateBits

opaque mask : Nat

axiom maskValue : mask = 281474976710655

axiom maskSuccessor : mask + 1 = modulus

opaque multiplier : Nat

axiom multiplierValue : multiplier = 25214903917

opaque addend : Nat

axiom addendValue : addend = 11

axiom stateValueBound (state : State) : stateValue state < modulus

opaque low48OfSigned : Int → Nat

axiom low48OfSignedBound (seed : Int) : low48OfSigned seed < modulus

axiom low48OfSignedCongruence (seed : Int) :
  Int.ofNat (low48OfSigned seed) = seed % Int.ofNat modulus

opaque mask48 : Nat → Nat

axiom mask48Semantics (value : Nat) : mask48 value = value % modulus

axiom mask48Bound (value : Nat) : mask48 value < modulus

axiom initialState : Int → State

axiom initialStateSemantics (seed : Int) :
  stateValue (initialState seed) =
    mask48 (Nat.xor (low48OfSigned seed) multiplier)

axiom nextState : State → State

axiom nextStateSemantics (state : State) :
  stateValue (nextState state) =
    (stateValue state * multiplier + addend) % modulus

axiom nextBits : State → Nat → Nat × State

axiom nextBitsSemantics
    (state : State) (bits : Nat) (positive : 0 < bits) (atMost32 : bits ≤ 32) :
  nextBits state bits =
    (stateValue (nextState state) / 2 ^ (stateBits - bits), nextState state)

axiom nextBitsRange
    (state : State) (bits : Nat) (positive : 0 < bits) (atMost32 : bits ≤ 32) :
  (nextBits state bits).1 < 2 ^ bits

theorem initialStateIs48Bit (seed : Int) :
    stateValue (initialState seed) < modulus :=
  stateValueBound (initialState seed)

theorem nextStateIs48Bit (state : State) :
    stateValue (nextState state) < modulus :=
  stateValueBound (nextState state)

theorem nextBitsAdvancesOnce
    (state : State) (bits : Nat) (positive : 0 < bits) (atMost32 : bits ≤ 32) :
    (nextBits state bits).2 = nextState state := by
  rw [nextBitsSemantics state bits positive atMost32]

theorem nextBits31Range (state : State) :
    (nextBits state 31).1 < 2147483648 := by
  simpa using nextBitsRange state 31 (by decide) (by decide)

theorem nextBits32Range (state : State) :
    (nextBits state 32).1 < 4294967296 := by
  simpa using nextBitsRange state 32 (by decide) (by decide)

axiom nextInt : State → Int × State

axiom nextIntSemantics (state : State) :
  let draw := nextBits state 32
  nextInt state =
    if draw.1 < 2147483648 then
      (Int.ofNat draw.1, draw.2)
    else
      (Int.ofNat draw.1 - 4294967296, draw.2)

axiom nextIntRange (state : State) :
  -2147483648 ≤ (nextInt state).1 ∧ (nextInt state).1 < 2147483648

theorem nextIntIsSigned32 (state : State) :
    -2147483648 ≤ (nextInt state).1 ∧ (nextInt state).1 < 2147483648 :=
  nextIntRange state

inductive RejectionSampling : State → Nat → Nat → State → Prop where
  | accept
      (state sampledState : State)
      (bound bits : Nat)
      (positive : 0 < bound)
      (draw : nextBits state 31 = (bits, sampledState))
      (accepted : bits - bits % bound + (bound - 1) < 2147483648) :
      RejectionSampling state bound (bits % bound) sampledState
  | retry
      (state sampledState finalState : State)
      (bound bits value : Nat)
      (positive : 0 < bound)
      (draw : nextBits state 31 = (bits, sampledState))
      (rejected : 2147483648 ≤ bits - bits % bound + (bound - 1))
      (rest : RejectionSampling sampledState bound value finalState) :
      RejectionSampling state bound value finalState

axiom nextIntBounded : State → Nat → Nat × State

axiom nextIntBoundedPowerOfTwo
    (state : State) (bound exponent : Nat)
    (positive : 0 < bound)
    (signedIntBound : bound < 2147483648)
    (powerOfTwo : bound = 2 ^ exponent) :
  let draw := nextBits state 31
  nextIntBounded state bound =
    (bound * draw.1 / 2147483648, draw.2)

axiom nextIntBoundedRejection
    (state finalState : State) (bound value : Nat)
    (positive : 0 < bound)
    (signedIntBound : bound < 2147483648)
    (notPowerOfTwo : ¬ ∃ exponent : Nat, bound = 2 ^ exponent) :
  nextIntBounded state bound = (value, finalState) ↔
    RejectionSampling state bound value finalState

axiom nextIntBoundedRange
    (state : State) (bound : Nat)
    (positive : 0 < bound) (signedIntBound : bound < 2147483648) :
  (nextIntBounded state bound).1 < bound

theorem rejectionSamplingRange
    (state finalState : State) (bound value : Nat)
    (sampling : RejectionSampling state bound value finalState) :
    value < bound := by
  induction sampling with
  | accept state sampledState bound bits positive draw accepted =>
      exact Nat.mod_lt bits positive
  | retry state sampledState finalState bound bits value positive draw rejected rest induction =>
      exact induction

theorem nextIntBoundedResultRange
    (state : State) (bound : Nat)
    (positive : 0 < bound) (signedIntBound : bound < 2147483648) :
    (nextIntBounded state bound).1 < bound :=
  nextIntBoundedRange state bound positive signedIntBound

inductive BoundedIntOutcome where
  | invalidBound
  | generated (value : Nat) (state : State)

axiom nextIntWithBound : State → Int → BoundedIntOutcome

axiom nextIntWithBoundInvalid
    (state : State) (bound : Int) (nonpositive : bound ≤ 0) :
  nextIntWithBound state bound = BoundedIntOutcome.invalidBound

axiom nextIntWithBoundValid
    (state : State) (bound : Int)
    (positive : 0 < bound) (signedIntBound : bound < 2147483648) :
  let naturalBound := bound.toNat
  let result := nextIntBounded state naturalBound
  nextIntWithBound state bound =
    BoundedIntOutcome.generated result.1 result.2

theorem nextIntWithBoundRejectsNonpositive
    (state : State) (bound : Int) (nonpositive : bound ≤ 0) :
    nextIntWithBound state bound = BoundedIntOutcome.invalidBound :=
  nextIntWithBoundInvalid state bound nonpositive

structure Fraction where
  numerator : Nat
  denominator : Nat

axiom nextFloat : State → Fraction × State

axiom nextFloatNumerator (state : State) :
  (nextFloat state).1.numerator = (nextBits state 24).1

axiom nextFloatDenominator (state : State) :
  (nextFloat state).1.denominator = 16777216

axiom nextFloatState (state : State) :
  (nextFloat state).2 = (nextBits state 24).2

theorem nextFloatNumeratorRange (state : State) :
    (nextFloat state).1.numerator < (nextFloat state).1.denominator := by
  rw [nextFloatNumerator, nextFloatDenominator]
  simpa using nextBitsRange state 24 (by decide) (by decide)

axiom nextDouble : State → Fraction × State

axiom nextDoubleNumerator (state : State) :
  let high := nextBits state 26
  let low := nextBits high.2 27
  (nextDouble state).1.numerator = high.1 * 134217728 + low.1

axiom nextDoubleDenominator (state : State) :
  (nextDouble state).1.denominator = 9007199254740992

axiom nextDoubleState (state : State) :
  let high := nextBits state 26
  let low := nextBits high.2 27
  (nextDouble state).2 = low.2

axiom nextDoubleNumeratorRange (state : State) :
  (nextDouble state).1.numerator < (nextDouble state).1.denominator

theorem nextDoubleIsUnitFraction (state : State) :
    (nextDouble state).1.numerator < (nextDouble state).1.denominator :=
  nextDoubleNumeratorRange state

end Spec.Random
