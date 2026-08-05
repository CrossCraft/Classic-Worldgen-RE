import Spec.Noise

namespace Spec.Terrain

structure Dimensions where
  width : Nat
  verticalSize : Nat
  depth : Nat

axiom validDimensions : Dimensions → Prop

axiom validDimensionsWidth (dimensions : Dimensions)
    (valid : validDimensions dimensions) :
  16 ≤ dimensions.width

axiom validDimensionsVerticalSize (dimensions : Dimensions)
    (valid : validDimensions dimensions) :
  16 ≤ dimensions.verticalSize

axiom validDimensionsDepth (dimensions : Dimensions)
    (valid : validDimensions dimensions) :
  16 ≤ dimensions.depth

opaque seaLevel : Dimensions → Nat

axiom seaLevelSemantics (dimensions : Dimensions) :
  seaLevel dimensions = dimensions.verticalSize / 2

theorem seaLevelIsHalfVerticalSize (dimensions : Dimensions) :
    seaLevel dimensions = dimensions.verticalSize / 2 :=
  seaLevelSemantics dimensions

opaque raisingCoordinate : Nat → Float

axiom raisingCoordinateSemantics (coordinate : Nat) :
  raisingCoordinate coordinate =
    Float32.toFloat
      (Float32.mul (Float32.ofInt (Int.ofNat coordinate)) (1.3 : Float32))

opaque truncateTowardZero : Float → Int

axiom truncateTowardZeroNonnegative
    (value : Float)
    (finite : value.isFinite = true)
    (nonnegative : 0.0 ≤ value)
    (upperBound : value < 2147483648.0) :
  truncateTowardZero value = Noise.floorCoordinate value

axiom truncateTowardZeroNegative
    (value : Float)
    (finite : value.isFinite = true)
    (lowerBound : -2147483648.0 ≤ value)
    (negative : value < 0.0) :
  truncateTowardZero value = -Noise.floorCoordinate (-value)

opaque halfTowardZero : Int → Int

axiom halfTowardZeroNonnegative (value : Int) (nonnegative : 0 ≤ value) :
  halfTowardZero value = Int.ofNat (value.toNat / 2)

axiom halfTowardZeroNegative (value : Int) (negative : value < 0) :
  halfTowardZero value = -Int.ofNat ((-value).toNat / 2)

opaque binary64Maximum : Float → Float → Float

axiom binary64MaximumLeft
    (left right : Float) (leftGreater : right < left) :
  binary64Maximum left right = left

axiom binary64MaximumRight
    (left right : Float) (rightGreater : left < right) :
  binary64Maximum left right = right

axiom binary64MaximumIdempotent (value : Float) :
  binary64Maximum value value = value

opaque distortedValue : Noise.OctaveNoise → Noise.OctaveNoise → Float → Float → Float

axiom distortedValueSemantics
    (carrier displacement : Noise.OctaveNoise) (x z : Float) :
  distortedValue carrier displacement x z =
    Noise.octaveValue carrier (x + Noise.octaveValue displacement x z) z

theorem distortionChangesFirstCoordinateOnly
    (carrier displacement : Noise.OctaveNoise) (x z : Float) :
    distortedValue carrier displacement x z =
      Noise.octaveValue carrier (x + Noise.octaveValue displacement x z) z :=
  distortedValueSemantics carrier displacement x z

structure ElevationNoise where
  lowerCarrier : Noise.OctaveNoise
  lowerDisplacement : Noise.OctaveNoise
  upperCarrier : Noise.OctaveNoise
  upperDisplacement : Noise.OctaveNoise
  selector : Noise.OctaveNoise
  erosionCarrier : Noise.OctaveNoise
  erosionDisplacement : Noise.OctaveNoise
  parityCarrier : Noise.OctaveNoise
  parityDisplacement : Noise.OctaveNoise
  strata : Noise.OctaveNoise

axiom elevationNoiseFromRandom : Random.State → ElevationNoise × Random.State

axiom elevationNoiseFromRandomSemantics (state : Random.State) :
  let lowerCarrier := Noise.octaveFromRandom state 8
  let lowerDisplacement := Noise.octaveFromRandom lowerCarrier.2 8
  let upperCarrier := Noise.octaveFromRandom lowerDisplacement.2 8
  let upperDisplacement := Noise.octaveFromRandom upperCarrier.2 8
  let selector := Noise.octaveFromRandom upperDisplacement.2 6
  let erosionCarrier := Noise.octaveFromRandom selector.2 8
  let erosionDisplacement := Noise.octaveFromRandom erosionCarrier.2 8
  let parityCarrier := Noise.octaveFromRandom erosionDisplacement.2 8
  let parityDisplacement := Noise.octaveFromRandom parityCarrier.2 8
  let strata := Noise.octaveFromRandom parityDisplacement.2 8
  (elevationNoiseFromRandom state).1 = {
    lowerCarrier := lowerCarrier.1
    lowerDisplacement := lowerDisplacement.1
    upperCarrier := upperCarrier.1
    upperDisplacement := upperDisplacement.1
    selector := selector.1
    erosionCarrier := erosionCarrier.1
    erosionDisplacement := erosionDisplacement.1
    parityCarrier := parityCarrier.1
    parityDisplacement := parityDisplacement.1
    strata := strata.1
  } ∧
  (elevationNoiseFromRandom state).2 = strata.2

opaque lowerElevationCandidate : ElevationNoise → Nat → Nat → Float

axiom lowerElevationCandidateSemantics
    (noise : ElevationNoise) (x z : Nat) :
  lowerElevationCandidate noise x z =
    distortedValue
      noise.lowerCarrier
      noise.lowerDisplacement
      (raisingCoordinate x)
      (raisingCoordinate z) / 6.0 + -4.0

opaque upperElevationCandidate : ElevationNoise → Nat → Nat → Float

axiom upperElevationCandidateSemantics
    (noise : ElevationNoise) (x z : Nat) :
  upperElevationCandidate noise x z =
    (distortedValue
      noise.upperCarrier
      noise.upperDisplacement
      (raisingCoordinate x)
      (raisingCoordinate z) / 5.0 + 10.0) + -4.0

opaque selectedElevationCandidate : ElevationNoise → Nat → Nat → Float

axiom selectedElevationCandidateSemantics
    (noise : ElevationNoise) (x z : Nat) :
  selectedElevationCandidate noise x z =
    if 0.0 < Noise.octaveValue noise.selector
        (Float.ofInt (Int.ofNat x)) (Float.ofInt (Int.ofNat z)) / 8.0 then
      lowerElevationCandidate noise x z
    else
      upperElevationCandidate noise x z

opaque raisedElevationValue : ElevationNoise → Nat → Nat → Float

axiom raisedElevationValueSemantics
    (noise : ElevationNoise) (x z : Nat) :
  let selected := binary64Maximum
    (lowerElevationCandidate noise x z)
    (selectedElevationCandidate noise x z) / 2.0
  raisedElevationValue noise x z =
    if selected < 0.0 then selected * 0.8 else selected

opaque raisedHeight : ElevationNoise → Nat → Nat → Int

axiom raisedHeightSemantics (noise : ElevationNoise) (x z : Nat) :
  raisedHeight noise x z = truncateTowardZero (raisedElevationValue noise x z)

axiom positiveSelectorUsesLowerCandidate
    (noise : ElevationNoise) (x z : Nat)
    (positive : 0.0 < Noise.octaveValue noise.selector
      (Float.ofInt (Int.ofNat x)) (Float.ofInt (Int.ofNat z)) / 8.0) :
  selectedElevationCandidate noise x z = lowerElevationCandidate noise x z

theorem positiveSelectorChoosesLowerField
    (noise : ElevationNoise) (x z : Nat)
    (positive : 0.0 < Noise.octaveValue noise.selector
      (Float.ofInt (Int.ofNat x)) (Float.ofInt (Int.ofNat z)) / 8.0) :
    selectedElevationCandidate noise x z = lowerElevationCandidate noise x z :=
  positiveSelectorUsesLowerCandidate noise x z positive

opaque erosionStrength : ElevationNoise → Nat → Nat → Float

axiom erosionStrengthSemantics (noise : ElevationNoise) (x z : Nat) :
  erosionStrength noise x z =
    distortedValue
      noise.erosionCarrier
      noise.erosionDisplacement
      (Float.ofInt (Int.ofNat (x * 2)))
      (Float.ofInt (Int.ofNat (z * 2))) / 8.0

opaque erosionParity : ElevationNoise → Nat → Nat → Int

axiom erosionParitySemantics (noise : ElevationNoise) (x z : Nat) :
  erosionParity noise x z =
    if 0.0 < distortedValue
        noise.parityCarrier
        noise.parityDisplacement
        (Float.ofInt (Int.ofNat (x * 2)))
        (Float.ofInt (Int.ofNat (z * 2))) then 1 else 0

opaque erodedHeight : ElevationNoise → Nat → Nat → Int

axiom erodedHeightSemantics (noise : ElevationNoise) (x z : Nat) :
  erodedHeight noise x z =
    if 2.0 < erosionStrength noise x z then
      halfTowardZero (raisedHeight noise x z - erosionParity noise x z) * 2 +
        erosionParity noise x z
    else
      raisedHeight noise x z

axiom erosionPreservesSelectedParity
    (noise : ElevationNoise) (x z : Nat)
    (active : 2.0 < erosionStrength noise x z) :
  (erodedHeight noise x z - erosionParity noise x z) % 2 = 0

theorem activeErosionQuantizesHeightParity
    (noise : ElevationNoise) (x z : Nat)
    (active : 2.0 < erosionStrength noise x z) :
    (erodedHeight noise x z - erosionParity noise x z) % 2 = 0 :=
  erosionPreservesSelectedParity noise x z active

opaque strataAdjustment : ElevationNoise → Nat → Nat → Int

axiom strataAdjustmentSemantics (noise : ElevationNoise) (x z : Nat) :
  strataAdjustment noise x z =
    truncateTowardZero
      (Noise.octaveValue noise.strata
        (Float.ofInt (Int.ofNat x))
        (Float.ofInt (Int.ofNat z)) / 24.0) - 4

opaque dirtTop : Dimensions → ElevationNoise → Nat → Nat → Int

axiom dirtTopSemantics
    (dimensions : Dimensions) (noise : ElevationNoise) (x z : Nat) :
  dirtTop dimensions noise x z =
    erodedHeight noise x z + Int.ofNat (seaLevel dimensions)

opaque stoneTop : Dimensions → ElevationNoise → Nat → Nat → Int

axiom stoneTopSemantics
    (dimensions : Dimensions) (noise : ElevationNoise) (x z : Nat) :
  stoneTop dimensions noise x z =
    dirtTop dimensions noise x z + strataAdjustment noise x z

opaque clampedSurfaceHeight : Dimensions → Int → Nat

axiom clampedSurfaceHeightLower
    (dimensions : Dimensions) (height : Int)
    (valid : validDimensions dimensions) :
  1 ≤ clampedSurfaceHeight dimensions height

axiom clampedSurfaceHeightUpper
    (dimensions : Dimensions) (height : Int)
    (valid : validDimensions dimensions) :
  clampedSurfaceHeight dimensions height ≤ dimensions.verticalSize - 2

axiom clampedSurfaceHeightInterior
    (dimensions : Dimensions) (height : Int)
    (lower : 1 ≤ height)
    (upper : height ≤ Int.ofNat (dimensions.verticalSize - 2)) :
  Int.ofNat (clampedSurfaceHeight dimensions height) = height

opaque surfaceHeight : Dimensions → ElevationNoise → Nat → Nat → Nat

axiom surfaceHeightSemantics
    (dimensions : Dimensions) (noise : ElevationNoise) (x z : Nat) :
  surfaceHeight dimensions noise x z =
    clampedSurfaceHeight dimensions
      (max (dirtTop dimensions noise x z) (stoneTop dimensions noise x z))

opaque airId : Nat
opaque stoneId : Nat
opaque grassId : Nat
opaque dirtId : Nat
opaque flowingWaterId : Nat
opaque stillWaterId : Nat
opaque flowingLavaId : Nat
opaque stillLavaId : Nat
opaque sandId : Nat
opaque gravelId : Nat

axiom airIdValue : airId = 0
axiom stoneIdValue : stoneId = 1
axiom grassIdValue : grassId = 2
axiom dirtIdValue : dirtId = 3
axiom flowingWaterIdValue : flowingWaterId = 8
axiom stillWaterIdValue : stillWaterId = 9
axiom flowingLavaIdValue : flowingLavaId = 10
axiom stillLavaIdValue : stillLavaId = 11
axiom sandIdValue : sandId = 12
axiom gravelIdValue : gravelId = 13

opaque BlockField : Type

axiom blockAt : BlockField → Nat → Nat → Nat → Nat

axiom soiledTerrain : Dimensions → ElevationNoise → BlockField

axiom soiledTerrainSemantics
    (dimensions : Dimensions) (noise : ElevationNoise) (x y z : Nat)
    (xBound : x < dimensions.width)
    (yBound : y < dimensions.verticalSize)
    (zBound : z < dimensions.depth) :
  blockAt (soiledTerrain dimensions noise) x y z =
    if y = 0 then flowingLavaId
    else if Int.ofNat y ≤ stoneTop dimensions noise x z then stoneId
    else if Int.ofNat y ≤ dirtTop dimensions noise x z then dirtId
    else airId

axiom soiledBottomIsLava
    (dimensions : Dimensions) (noise : ElevationNoise) (x z : Nat)
    (xBound : x < dimensions.width)
    (zBound : z < dimensions.depth) :
  blockAt (soiledTerrain dimensions noise) x 0 z = flowingLavaId

theorem bottomLayerStartsAsFlowingLava
    (dimensions : Dimensions) (noise : ElevationNoise) (x z : Nat)
    (xBound : x < dimensions.width)
    (zBound : z < dimensions.depth) :
    blockAt (soiledTerrain dimensions noise) x 0 z = flowingLavaId :=
  soiledBottomIsLava dimensions noise x z xBound zBound

axiom stoneOccupiesLowerStratum
    (dimensions : Dimensions) (noise : ElevationNoise) (x y z : Nat)
    (xBound : x < dimensions.width)
    (yPositive : 0 < y)
    (yBound : y < dimensions.verticalSize)
    (zBound : z < dimensions.depth)
    (belowStone : Int.ofNat y ≤ stoneTop dimensions noise x z) :
  blockAt (soiledTerrain dimensions noise) x y z = stoneId

axiom dirtOccupiesMiddleStratum
    (dimensions : Dimensions) (noise : ElevationNoise) (x y z : Nat)
    (xBound : x < dimensions.width)
    (aboveStone : stoneTop dimensions noise x z < Int.ofNat y)
    (belowDirt : Int.ofNat y ≤ dirtTop dimensions noise x z)
    (yBound : y < dimensions.verticalSize)
    (zBound : z < dimensions.depth) :
  blockAt (soiledTerrain dimensions noise) x y z = dirtId

theorem initialVerticalStrata
    (dimensions : Dimensions) (noise : ElevationNoise) (x y z : Nat)
    (xBound : x < dimensions.width)
    (yPositive : 0 < y)
    (yBound : y < dimensions.verticalSize)
    (zBound : z < dimensions.depth) :
    (Int.ofNat y ≤ stoneTop dimensions noise x z →
      blockAt (soiledTerrain dimensions noise) x y z = stoneId) ∧
    (stoneTop dimensions noise x z < Int.ofNat y →
      Int.ofNat y ≤ dirtTop dimensions noise x z →
      blockAt (soiledTerrain dimensions noise) x y z = dirtId) :=
  ⟨fun below => stoneOccupiesLowerStratum
      dimensions noise x y z xBound yPositive yBound zBound below,
    fun above below => dirtOccupiesMiddleStratum
      dimensions noise x y z xBound above below yBound zBound⟩

structure Position where
  x : Nat
  y : Nat
  z : Nat

axiom inside : Dimensions → Position → Prop

axiom insideSemantics (dimensions : Dimensions) (position : Position) :
  inside dimensions position ↔
    position.x < dimensions.width ∧
    position.y < dimensions.verticalSize ∧
    position.z < dimensions.depth

inductive FloodReachable
    (dimensions : Dimensions) (field : BlockField) (source : Position) :
    Position → Prop where
  | origin
      (sourceInside : inside dimensions source)
      (sourceAir : blockAt field source.x source.y source.z = airId) :
      FloodReachable dimensions field source source
  | east
      (position : Position)
      (reachable : FloodReachable dimensions field source position)
      (targetInside : inside dimensions {
        x := position.x + 1, y := position.y, z := position.z })
      (targetAir : blockAt field (position.x + 1) position.y position.z = airId) :
      FloodReachable dimensions field source {
        x := position.x + 1, y := position.y, z := position.z }
  | west
      (x y z : Nat)
      (reachable : FloodReachable dimensions field source { x := x + 1, y := y, z := z })
      (targetInside : inside dimensions { x := x, y := y, z := z })
      (targetAir : blockAt field x y z = airId) :
      FloodReachable dimensions field source { x := x, y := y, z := z }
  | south
      (position : Position)
      (reachable : FloodReachable dimensions field source position)
      (targetInside : inside dimensions {
        x := position.x, y := position.y, z := position.z + 1 })
      (targetAir : blockAt field position.x position.y (position.z + 1) = airId) :
      FloodReachable dimensions field source {
        x := position.x, y := position.y, z := position.z + 1 }
  | north
      (x y z : Nat)
      (reachable : FloodReachable dimensions field source { x := x, y := y, z := z + 1 })
      (targetInside : inside dimensions { x := x, y := y, z := z })
      (targetAir : blockAt field x y z = airId) :
      FloodReachable dimensions field source { x := x, y := y, z := z }
  | downward
      (x y z : Nat)
      (reachable : FloodReachable dimensions field source { x := x, y := y + 1, z := z })
      (targetInside : inside dimensions { x := x, y := y, z := z })
      (targetAir : blockAt field x y z = airId) :
      FloodReachable dimensions field source { x := x, y := y, z := z }

theorem floodReachabilityNeverMovesUpward
    (dimensions : Dimensions) (field : BlockField) (source target : Position)
    (reachable : FloodReachable dimensions field source target) :
    target.y ≤ source.y := by
  induction reachable with
  | origin sourceInside sourceAir => simp
  | east position reachable targetInside targetAir induction => simpa using induction
  | west x y z reachable targetInside targetAir induction => simpa using induction
  | south position reachable targetInside targetAir induction => simpa using induction
  | north x y z reachable targetInside targetAir induction => simpa using induction
  | downward x y z reachable targetInside targetAir induction =>
      exact Nat.le_trans (Nat.le_succ y) (by simpa using induction)

theorem floodReachabilityStartsInAir
    (dimensions : Dimensions) (field : BlockField) (source target : Position)
    (reachable : FloodReachable dimensions field source target) :
    blockAt field source.x source.y source.z = airId := by
  induction reachable with
  | origin sourceInside sourceAir => exact sourceAir
  | east position reachable targetInside targetAir induction => exact induction
  | west x y z reachable targetInside targetAir induction => exact induction
  | south position reachable targetInside targetAir induction => exact induction
  | north x y z reachable targetInside targetAir induction => exact induction
  | downward x y z reachable targetInside targetAir induction => exact induction

axiom floodFill : Dimensions → BlockField → Position → Nat → BlockField

axiom floodFillReachable
    (dimensions : Dimensions) (field : BlockField) (source target : Position)
    (fluidId : Nat)
    (reachable : FloodReachable dimensions field source target) :
  blockAt (floodFill dimensions field source fluidId)
    target.x target.y target.z = fluidId

axiom floodFillLavaWaterReaction
    (dimensions : Dimensions) (field : BlockField) (source target above : Position)
    (fluidId : Nat)
    (lava : fluidId = flowingLavaId ∨ fluidId = stillLavaId)
    (aboveTarget : above.x = target.x ∧ above.y = target.y + 1 ∧ above.z = target.z)
    (reachable : FloodReachable dimensions field source above)
    (water : blockAt field target.x target.y target.z = flowingWaterId ∨
      blockAt field target.x target.y target.z = stillWaterId) :
  blockAt (floodFill dimensions field source fluidId)
    target.x target.y target.z = stoneId

axiom floodFillUnchanged
    (dimensions : Dimensions) (field : BlockField) (source target : Position)
    (fluidId : Nat)
    (notReached : ¬ FloodReachable dimensions field source target)
    (notReaction : ¬ ∃ above : Position,
      (fluidId = flowingLavaId ∨ fluidId = stillLavaId) ∧
      above.x = target.x ∧ above.y = target.y + 1 ∧ above.z = target.z ∧
      FloodReachable dimensions field source above ∧
      (blockAt field target.x target.y target.z = flowingWaterId ∨
        blockAt field target.x target.y target.z = stillWaterId)) :
  blockAt (floodFill dimensions field source fluidId)
    target.x target.y target.z = blockAt field target.x target.y target.z

axiom boundaryWaterSource : Dimensions → Position → Prop

axiom boundaryWaterSourceSemantics
    (dimensions : Dimensions) (source : Position) :
  boundaryWaterSource dimensions source ↔
    inside dimensions source ∧
    source.y + 1 = seaLevel dimensions ∧
    (source.x = 0 ∨ source.x + 1 = dimensions.width ∨
      source.z = 0 ∨ source.z + 1 = dimensions.depth)

opaque floodSubmissionEntry :
  Dimensions → BlockField → Position → Position → Prop

axiom floodSubmissionEntrySemantics
    (dimensions : Dimensions) (field : BlockField)
    (source entry : Position) :
  floodSubmissionEntry dimensions field source entry ↔
    inside dimensions source ∧
    inside dimensions entry ∧
    entry.y = source.y ∧
    entry.z = source.z ∧
    entry.x ≤ source.x ∧
    blockAt field entry.x entry.y entry.z = airId ∧
    ∀ x : Nat, entry.x ≤ x → x < source.x →
      blockAt field x source.y source.z = airId

axiom boundaryWaterPass : Dimensions → BlockField → BlockField

axiom boundaryWaterPassFilled
    (dimensions : Dimensions) (field : BlockField) (target : Position)
    (reached : ∃ source entry : Position,
      boundaryWaterSource dimensions source ∧
      floodSubmissionEntry dimensions field source entry ∧
      FloodReachable dimensions field entry target) :
  blockAt (boundaryWaterPass dimensions field)
    target.x target.y target.z = stillWaterId

axiom boundaryWaterPassUnchanged
    (dimensions : Dimensions) (field : BlockField) (target : Position)
    (notReached : ¬ ∃ source entry : Position,
      boundaryWaterSource dimensions source ∧
      floodSubmissionEntry dimensions field source entry ∧
      FloodReachable dimensions field entry target) :
  blockAt (boundaryWaterPass dimensions field)
    target.x target.y target.z = blockAt field target.x target.y target.z

theorem boundaryWaterFillsEveryDownwardReachableAirCell
    (dimensions : Dimensions) (field : BlockField) (source target : Position)
    (boundary : boundaryWaterSource dimensions source)
    (reachable : FloodReachable dimensions field source target) :
    blockAt (boundaryWaterPass dimensions field)
      target.x target.y target.z = stillWaterId :=
  boundaryWaterPassFilled dimensions field target ⟨source, source, boundary,
    (floodSubmissionEntrySemantics dimensions field source source).mpr
      ⟨(boundaryWaterSourceSemantics dimensions source).mp boundary |>.1,
        (boundaryWaterSourceSemantics dimensions source).mp boundary |>.1,
        rfl, rfl, Nat.le_refl source.x,
        floodReachabilityStartsInAir dimensions field source target reachable,
        by omega⟩,
    reachable⟩

theorem blockedBoundarySourceUsesWestwardAirInterval
    (dimensions : Dimensions) (field : BlockField)
    (source entry target : Position)
    (boundary : boundaryWaterSource dimensions source)
    (entryInside : inside dimensions entry)
    (sameY : entry.y = source.y)
    (sameZ : entry.z = source.z)
    (west : entry.x < source.x)
    (entryAir : blockAt field entry.x entry.y entry.z = airId)
    (intervalAir : ∀ x : Nat, entry.x ≤ x → x < source.x →
      blockAt field x source.y source.z = airId)
    (_sourceBlocked : blockAt field source.x source.y source.z ≠ airId)
    (reachable : FloodReachable dimensions field entry target) :
  blockAt (boundaryWaterPass dimensions field)
      target.x target.y target.z = stillWaterId :=
  boundaryWaterPassFilled dimensions field target ⟨source, entry, boundary,
    (floodSubmissionEntrySemantics dimensions field source entry).mpr
      ⟨(boundaryWaterSourceSemantics dimensions source).mp boundary |>.1,
        entryInside, sameY, sameZ, Nat.le_of_lt west, entryAir, intervalAir⟩,
    reachable⟩

inductive InlandWaterPlacement :
    Nat → Dimensions → Random.State → BlockField → Random.State → BlockField → Prop where
  | done (dimensions : Dimensions) (state : Random.State) (field : BlockField) :
      InlandWaterPlacement 0 dimensions state field state field
  | step
      (remaining : Nat)
      (dimensions : Dimensions)
      (state xState yState zState finalState : Random.State)
      (field finalField : BlockField)
      (x yOffset z : Nat)
      (xDraw : Random.nextIntBounded state dimensions.width = (x, xState))
      (yDraw : Random.nextIntBounded xState 2 = (yOffset, yState))
      (zDraw : Random.nextIntBounded yState dimensions.depth = (z, zState))
      (rest : InlandWaterPlacement remaining dimensions zState
        (floodFill dimensions field {
          x := x, y := seaLevel dimensions - 1 - yOffset, z := z } stillWaterId)
        finalState finalField) :
      InlandWaterPlacement (remaining + 1) dimensions state field finalState finalField

axiom inlandWaterPass :
  Dimensions → Random.State → BlockField → Random.State × BlockField

axiom inlandWaterPassSemantics
    (dimensions : Dimensions) (state : Random.State) (field : BlockField) :
  InlandWaterPlacement
    (dimensions.width * dimensions.depth / 8000)
    dimensions state field
    (inlandWaterPass dimensions state field).1
    (inlandWaterPass dimensions state field).2

opaque fractionValue32 : Random.Fraction → Float32

axiom fractionValue32Semantics (fraction : Random.Fraction) :
  fractionValue32 fraction =
    Float32.div
      (Float32.ofInt (Int.ofNat fraction.numerator))
      (Float32.ofInt (Int.ofNat fraction.denominator))

opaque lavaSourceLevel : Dimensions → Random.Fraction → Random.Fraction → Nat

axiom lavaSourceLevelSemantics
    (dimensions : Dimensions) (first second : Random.Fraction) :
  Int.ofNat (lavaSourceLevel dimensions first second) =
    truncateTowardZero
      (Float32.toFloat
        (Float32.mul
          (Float32.mul (fractionValue32 first) (fractionValue32 second))
          (Float32.ofInt (Int.ofNat (seaLevel dimensions - 3)))))

inductive LavaPlacement :
    Nat → Dimensions → Random.State → BlockField → Random.State → BlockField → Prop where
  | done (dimensions : Dimensions) (state : Random.State) (field : BlockField) :
      LavaPlacement 0 dimensions state field state field
  | step
      (remaining : Nat)
      (dimensions : Dimensions)
      (state xState firstState secondState zState finalState : Random.State)
      (field finalField : BlockField)
      (x z : Nat)
      (first second : Random.Fraction)
      (xDraw : Random.nextIntBounded state dimensions.width = (x, xState))
      (firstDraw : Random.nextFloat xState = (first, firstState))
      (secondDraw : Random.nextFloat firstState = (second, secondState))
      (zDraw : Random.nextIntBounded secondState dimensions.depth = (z, zState))
      (rest : LavaPlacement remaining dimensions zState
        (floodFill dimensions field {
          x := x, y := lavaSourceLevel dimensions first second, z := z } stillLavaId)
        finalState finalField) :
      LavaPlacement (remaining + 1) dimensions state field finalState finalField

axiom lavaPass :
  Dimensions → Random.State → BlockField → Random.State × BlockField

axiom lavaPassSemantics
    (dimensions : Dimensions) (state : Random.State) (field : BlockField) :
  LavaPlacement
    (dimensions.width * dimensions.verticalSize * dimensions.depth / 20000)
    dimensions state field
    (lavaPass dimensions state field).1
    (lavaPass dimensions state field).2

structure SurfaceNoise where
  sand : Noise.OctaveNoise
  gravel : Noise.OctaveNoise

axiom surfaceNoiseFromRandom : Random.State → SurfaceNoise × Random.State

axiom surfaceNoiseFromRandomSemantics (state : Random.State) :
  let sand := Noise.octaveFromRandom state 8
  let gravel := Noise.octaveFromRandom sand.2 8
  (surfaceNoiseFromRandom state).1 = { sand := sand.1, gravel := gravel.1 } ∧
  (surfaceNoiseFromRandom state).2 = gravel.2

axiom surfacedTerrain :
  Dimensions → ElevationNoise → SurfaceNoise → BlockField → BlockField

axiom surfacedTerrainSemantics
    (dimensions : Dimensions)
    (elevationNoise : ElevationNoise)
    (surfaceNoise : SurfaceNoise)
    (field : BlockField)
    (x z : Nat)
    (xBound : x < dimensions.width)
    (zBound : z < dimensions.depth) :
  let top := surfaceHeight dimensions elevationNoise x z
  let above := blockAt field x (top + 1) z
  blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field) x top z =
    if (above = flowingWaterId ∨ above = stillWaterId) ∧
        top ≤ dimensions.verticalSize / 2 - 1 ∧
        12.0 < Noise.octaveValue surfaceNoise.gravel
          (Float.ofInt (Int.ofNat x)) (Float.ofInt (Int.ofNat z)) then
      gravelId
    else if above = airId then
      if top ≤ dimensions.verticalSize / 2 - 1 ∧
          8.0 < Noise.octaveValue surfaceNoise.sand
            (Float.ofInt (Int.ofNat x)) (Float.ofInt (Int.ofNat z)) then
        sandId
      else
        grassId
    else
      blockAt field x top z

axiom surfacedTerrainUnchangedAwayFromSurface
    (dimensions : Dimensions)
    (elevationNoise : ElevationNoise)
    (surfaceNoise : SurfaceNoise)
    (field : BlockField)
    (x y z : Nat)
    (xBound : x < dimensions.width)
    (yBound : y < dimensions.verticalSize)
    (zBound : z < dimensions.depth)
    (away : y ≠ surfaceHeight dimensions elevationNoise x z) :
  blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field) x y z =
    blockAt field x y z

axiom exposedSurfaceIsGrassOrSand
    (dimensions : Dimensions)
    (elevationNoise : ElevationNoise)
    (surfaceNoise : SurfaceNoise)
    (field : BlockField)
    (x z : Nat)
    (xBound : x < dimensions.width)
    (zBound : z < dimensions.depth)
    (exposed : blockAt field x
      (surfaceHeight dimensions elevationNoise x z + 1) z = airId) :
  blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field)
      x (surfaceHeight dimensions elevationNoise x z) z = grassId ∨
    blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field)
      x (surfaceHeight dimensions elevationNoise x z) z = sandId

theorem dryExposedTerrainReceivesAPlantableSurface
    (dimensions : Dimensions)
    (elevationNoise : ElevationNoise)
    (surfaceNoise : SurfaceNoise)
    (field : BlockField)
    (x z : Nat)
    (xBound : x < dimensions.width)
    (zBound : z < dimensions.depth)
    (exposed : blockAt field x
      (surfaceHeight dimensions elevationNoise x z + 1) z = airId) :
    blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field)
        x (surfaceHeight dimensions elevationNoise x z) z = grassId ∨
      blockAt (surfacedTerrain dimensions elevationNoise surfaceNoise field)
        x (surfaceHeight dimensions elevationNoise x z) z = sandId :=
  exposedSurfaceIsGrassOrSand
    dimensions elevationNoise surfaceNoise field x z xBound zBound exposed

end Spec.Terrain
