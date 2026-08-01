import Spec.Random

namespace Spec.Noise

opaque Table : Type

axiom tableEntry : Table → Nat → Nat

axiom identityTable : Table

axiom identityTableEntry (index : Nat) (bound : index < 256) :
  tableEntry identityTable index = index

axiom swapTable : Table → Nat → Nat → Table

axiom swapTableSemantics (table : Table) (left right index : Nat) :
  tableEntry (swapTable table left right) index =
    if index = left then tableEntry table right
    else if index = right then tableEntry table left
    else tableEntry table index

inductive PermutationShuffle : Nat → Random.State → Table → Random.State → Table → Prop where
  | done (state : Random.State) (table : Table) :
      PermutationShuffle 256 state table state table
  | step
      (index draw : Nat)
      (state sampledState finalState : Random.State)
      (table finalTable : Table)
      (indexBound : index < 256)
      (sample : Random.nextIntBounded state (256 - index) = (draw, sampledState))
      (rest : PermutationShuffle
        (index + 1)
        sampledState
        (swapTable table index (index + draw))
        finalState
        finalTable) :
      PermutationShuffle index state table finalState finalTable

opaque Permutation : Type

axiom firstHalf : Permutation → Table

axiom permutationEntry : Permutation → Nat → Nat

axiom duplicatedPermutationEntry
    (permutation : Permutation) (index : Nat) (bound : index < 512) :
  permutationEntry permutation index =
    tableEntry (firstHalf permutation) (index % 256)

axiom permutationEntryBound
    (permutation : Permutation) (index : Nat) (bound : index < 512) :
  permutationEntry permutation index < 256

axiom permutationFirstHalfBijection (permutation : Permutation) (value : Nat)
    (valueBound : value < 256) :
  ∃ index : Nat,
    index < 256 ∧
      permutationEntry permutation index = value ∧
      ∀ other : Nat,
        other < 256 →
        permutationEntry permutation other = value →
        other = index

axiom permutationFromRandom : Random.State → Permutation × Random.State

axiom permutationFromRandomSemantics (state : Random.State) :
  PermutationShuffle
    0
    state
    identityTable
    (permutationFromRandom state).2
    (firstHalf (permutationFromRandom state).1)

theorem permutationConstructionIsForwardFisherYates (state : Random.State) :
    PermutationShuffle
      0
      state
      identityTable
      (permutationFromRandom state).2
      (firstHalf (permutationFromRandom state).1) :=
  permutationFromRandomSemantics state

theorem permutationSecondHalfDuplicatesFirst
    (permutation : Permutation) (index : Nat) (bound : index < 256) :
    permutationEntry permutation (index + 256) =
      permutationEntry permutation index := by
  rw [duplicatedPermutationEntry permutation (index + 256) (by omega)]
  rw [duplicatedPermutationEntry permutation index (by omega)]
  simp

opaque floorCoordinate : Float → Int

axiom floorCoordinateSemantics
    (coordinate : Float)
    (finite : coordinate.isFinite = true)
    (lowerBound : -2147483648.0 ≤ coordinate)
    (upperBound : coordinate < 2147483648.0) :
  Float.ofInt (floorCoordinate coordinate) = coordinate.floor

axiom floorCoordinateAtInteger
    (coordinate : Int)
    (lowerBound : -2147483648 ≤ coordinate)
    (upperBound : coordinate < 2147483648) :
  floorCoordinate (Float.ofInt coordinate) = coordinate

opaque fade : Float → Float

axiom fadeSemantics (parameter : Float) :
  fade parameter =
    parameter * parameter * parameter *
      (parameter * (parameter * 6.0 - 15.0) + 10.0)

axiom fadeAtZero : fade 0.0 = 0.0

axiom fadeAtOne : fade 1.0 = 1.0

theorem fadeEndpoints : fade 0.0 = 0.0 ∧ fade 1.0 = 1.0 :=
  ⟨fadeAtZero, fadeAtOne⟩

opaque interpolate : Float → Float → Float → Float

axiom interpolateSemantics (weight lower upper : Float) :
  interpolate weight lower upper = lower + weight * (upper - lower)

axiom interpolateAtZero (lower upper : Float) :
  interpolate 0.0 lower upper = lower

axiom interpolateAtOne (lower upper : Float) :
  interpolate 1.0 lower upper = upper

theorem interpolationEndpoints (lower upper : Float) :
    interpolate 0.0 lower upper = lower ∧
      interpolate 1.0 lower upper = upper :=
  ⟨interpolateAtZero lower upper, interpolateAtOne lower upper⟩

opaque gradient : Nat → Float → Float → Float → Float

axiom gradientSemantics (hash : Nat) (x y z : Float) :
  let nibble := hash % 16
  let first := if nibble < 8 then x else y
  let second :=
    if nibble < 4 then y
    else if nibble = 12 ∨ nibble = 14 then x
    else z
  gradient hash x y z =
    (if nibble % 2 = 0 then first else -first) +
      (if (nibble / 2) % 2 = 0 then second else -second)

axiom gradientNibbleInvariant
    (hash : Nat) (x y z : Float) :
  gradient (hash + 16) x y z = gradient hash x y z

theorem gradientSelectionUsesLowFourBits
    (hash : Nat) (x y z : Float) :
    gradient (hash + 16) x y z = gradient hash x y z :=
  gradientNibbleInvariant hash x y z

opaque wrapCoordinate : Int → Nat

axiom wrapCoordinateBound (coordinate : Int) :
  wrapCoordinate coordinate < 256

axiom wrapCoordinateSemantics (coordinate : Int) :
  Int.ofNat (wrapCoordinate coordinate) = coordinate % 256

opaque latticeHash : Permutation → Int → Int → Int → Nat

axiom latticeHashSemantics
    (permutation : Permutation) (x y z : Int) :
  let xHash := permutationEntry permutation (wrapCoordinate x)
  let xyHash :=
    permutationEntry permutation (xHash + wrapCoordinate y)
  latticeHash permutation x y z =
    permutationEntry permutation (xyHash + wrapCoordinate z)

axiom latticeHashBound
    (permutation : Permutation) (x y z : Int) :
  latticeHash permutation x y z < 256

theorem latticeHashIsByteSized
    (permutation : Permutation) (x y z : Int) :
    latticeHash permutation x y z < 256 :=
  latticeHashBound permutation x y z

opaque gradientNoise : Permutation → Float → Float → Float

axiom gradientNoiseSemantics
    (permutation : Permutation) (x y : Float) :
  let latticeX := floorCoordinate x
  let latticeY := floorCoordinate y
  let zeroInt : Int := 0
  let oneInt : Int := 1
  let zero := Float.ofInt zeroInt
  let one := Float.ofInt oneInt
  let offsetX := x - Float.ofInt latticeX
  let offsetY := y - Float.ofInt latticeY
  let offsetZ := zero
  let fadedX := fade offsetX
  let fadedY := fade offsetY
  let fadedZ := fade offsetZ
  let lowerXLowerY := interpolate fadedX
    (gradient
      (latticeHash permutation latticeX latticeY zeroInt)
      offsetX offsetY offsetZ)
    (gradient
      (latticeHash permutation (latticeX + oneInt) latticeY zeroInt)
      (offsetX - one) offsetY offsetZ)
  let upperXLowerY := interpolate fadedX
    (gradient
      (latticeHash permutation latticeX (latticeY + oneInt) zeroInt)
      offsetX (offsetY - one) offsetZ)
    (gradient
      (latticeHash permutation (latticeX + oneInt) (latticeY + oneInt) zeroInt)
      (offsetX - one) (offsetY - one) offsetZ)
  let lowerZ := interpolate fadedY lowerXLowerY upperXLowerY
  let lowerXUpperY := interpolate fadedX
    (gradient
      (latticeHash permutation latticeX latticeY oneInt)
      offsetX offsetY (offsetZ - one))
    (gradient
      (latticeHash permutation (latticeX + oneInt) latticeY oneInt)
      (offsetX - one) offsetY (offsetZ - one))
  let upperXUpperY := interpolate fadedX
    (gradient
      (latticeHash permutation latticeX (latticeY + oneInt) oneInt)
      offsetX (offsetY - one) (offsetZ - one))
    (gradient
      (latticeHash permutation (latticeX + oneInt) (latticeY + oneInt) oneInt)
      (offsetX - one) (offsetY - one) (offsetZ - one))
  let upperZ := interpolate fadedY lowerXUpperY upperXUpperY
  gradientNoise permutation x y = interpolate fadedZ lowerZ upperZ

opaque OctaveNoise : Type

axiom octaveCount : OctaveNoise → Nat

axiom octavePermutation : OctaveNoise → Nat → Permutation

axiom octaveState : OctaveNoise → Nat → Random.State

axiom octaveFromRandom : Random.State → Nat → OctaveNoise × Random.State

axiom octaveFromRandomCount (state : Random.State) (count : Nat) :
  octaveCount (octaveFromRandom state count).1 = count

axiom octaveFromRandomInitialState (state : Random.State) (count : Nat) :
  octaveState (octaveFromRandom state count).1 0 = state

axiom octaveFromRandomStep
    (state : Random.State) (count index : Nat) (indexBound : index < count) :
  let noise := (octaveFromRandom state count).1
  permutationFromRandom (octaveState noise index) =
    (octavePermutation noise index, octaveState noise (index + 1))

axiom octaveFromRandomFinalState (state : Random.State) (count : Nat) :
  octaveState (octaveFromRandom state count).1 count =
    (octaveFromRandom state count).2

theorem octaveConstructionConsumesOnePermutationPerIndex
    (state : Random.State) (count index : Nat) (indexBound : index < count) :
    let noise := (octaveFromRandom state count).1
    permutationFromRandom (octaveState noise index) =
      (octavePermutation noise index, octaveState noise (index + 1)) :=
  octaveFromRandomStep state count index indexBound

opaque powerOfTwo : Nat → Float

axiom powerOfTwoZero : powerOfTwo 0 = 1.0

axiom powerOfTwoSuccessor (index : Nat) :
  powerOfTwo (index + 1) = powerOfTwo index * 2.0

opaque amplitudeScale : Nat → Float

axiom amplitudeScaleSemantics (index : Nat) :
  amplitudeScale index = powerOfTwo index

opaque frequencyScale : Nat → Float

axiom frequencyScaleSemantics (index : Nat) :
  frequencyScale index = 1.0 / powerOfTwo index

axiom constructorOrderFrequencyHalving (index : Nat) (safe : index < 1022) :
  frequencyScale (index + 1) = frequencyScale index / 2.0

axiom constructorOrderAmplitudeDoubling (index : Nat) :
  amplitudeScale (index + 1) = amplitudeScale index * 2.0

axiom coarseToFineFrequencyDoubling (index : Nat) (safe : index < 1022) :
  frequencyScale index = frequencyScale (index + 1) * 2.0

axiom coarseToFineAmplitudeHalving (index : Nat) :
  amplitudeScale index = amplitudeScale (index + 1) / 2.0

theorem coarseToFineScaling (index : Nat) (safe : index < 1022) :
    frequencyScale index = frequencyScale (index + 1) * 2.0 ∧
      amplitudeScale index = amplitudeScale (index + 1) / 2.0 :=
  ⟨coarseToFineFrequencyDoubling index safe,
    coarseToFineAmplitudeHalving index⟩

opaque octaveTerm : OctaveNoise → Nat → Float → Float → Float

axiom octaveTermSemantics
    (noise : OctaveNoise) (index : Nat) (x y : Float)
    (indexBound : index < octaveCount noise) :
  octaveTerm noise index x y =
    gradientNoise
      (octavePermutation noise index)
      (x / powerOfTwo index)
      (y / powerOfTwo index) *
    powerOfTwo index

opaque partialOctaveSum : OctaveNoise → Nat → Float → Float → Float

axiom partialOctaveSumZero (noise : OctaveNoise) (x y : Float) :
  partialOctaveSum noise 0 x y = 0.0

axiom partialOctaveSumSuccessor
    (noise : OctaveNoise) (count : Nat) (x y : Float)
    (countBound : count < octaveCount noise) :
  partialOctaveSum noise (count + 1) x y =
    partialOctaveSum noise count x y + octaveTerm noise count x y

opaque octaveValue : OctaveNoise → Float → Float → Float

axiom octaveValueSemantics (noise : OctaveNoise) (x y : Float) :
  octaveValue noise x y = partialOctaveSum noise (octaveCount noise) x y

theorem octaveValueIsFiniteIndexedSum (noise : OctaveNoise) (x y : Float) :
    octaveValue noise x y =
      partialOctaveSum noise (octaveCount noise) x y :=
  octaveValueSemantics noise x y

end Spec.Noise
