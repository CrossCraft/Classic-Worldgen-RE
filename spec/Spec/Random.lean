namespace Spec.Random

opaque State : Type

axiom initialState : Int → State

axiom nextBits : State → Nat → Nat × State

axiom multiplier : Nat

axiom multiplierValue : multiplier = 25214903917

axiom addend : Nat

axiom addendValue : addend = 11

axiom stateBits : Nat

axiom stateBitsValue : stateBits = 48

theorem nextBitsDeterministic (s : State) (b : Nat) : nextBits s b = nextBits s b := rfl

theorem stateModulus : ∃ m : Nat, m = 2 ^ stateBits := by
  sorry

end Spec.Random
