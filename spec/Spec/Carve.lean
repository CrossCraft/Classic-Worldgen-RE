import Spec.Terrain

namespace Spec.Carve

opaque pi32 : Float32

axiom pi32Value : pi32 = 3.1415927

opaque pi64 : Float

axiom pi64Value : pi64 = 3.141592653589793

opaque binary64Sine : Float → Float

axiom binary64SineSemantics (angle : Float) :
  binary64Sine angle = Float.sin angle

opaque binary32Round : Float → Float32

opaque sineTable : Nat → Float32

axiom sineTablePeriod (index : Nat) :
  sineTable (index + 65536) = sineTable index

axiom sineTableSemantics (index : Nat) (bound : index < 65536) :
  sineTable index = binary32Round
    (binary64Sine
      (Float.ofInt (Int.ofNat index) * pi64 * 2.0 / 65536.0))

opaque truncateFloat32TowardZero : Float32 → Int

axiom truncateFloat32TowardZeroSemantics (value : Float32) :
  truncateFloat32TowardZero value =
    Terrain.truncateTowardZero (Float32.toFloat value)

opaque low16OfInt : Int → Nat

axiom low16OfIntBound (value : Int) : low16OfInt value < 65536

axiom low16OfIntCongruence (value : Int) :
  Int.ofNat (low16OfInt value) = value % 65536

opaque trajectorySine : Float32 → Float32

axiom trajectorySineSemantics (angle : Float32) :
  trajectorySine angle = sineTable
    (low16OfInt
      (truncateFloat32TowardZero
        (Float32.mul angle 10430.378)))

opaque trajectoryCosine : Float32 → Float32

axiom trajectoryCosineSemantics (angle : Float32) :
  trajectoryCosine angle = sineTable
    (low16OfInt
      (truncateFloat32TowardZero
        (Float32.add (Float32.mul angle 10430.378) 16384.0)))

opaque caveAttemptCount : Terrain.Dimensions → Nat

axiom caveAttemptCountSemantics (dimensions : Terrain.Dimensions) :
  caveAttemptCount dimensions =
    ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) * 2

theorem caveCountScalesWithVolume (dimensions : Terrain.Dimensions) :
    caveAttemptCount dimensions =
      ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) * 2 :=
  caveAttemptCountSemantics dimensions

structure Point32 where
  x : Float32
  y : Float32
  z : Float32

structure CaveSeed where
  start : Point32
  length : Nat
  yaw : Float32
  pitch : Float32
  radiusFactor : Float32

axiom caveSeedFromRandom :
  Terrain.Dimensions → Random.State → CaveSeed × Random.State

axiom caveSeedFromRandomSemantics
    (dimensions : Terrain.Dimensions) (state : Random.State) :
  let x := Random.nextFloat state
  let y := Random.nextFloat x.2
  let z := Random.nextFloat y.2
  let lengthFirst := Random.nextFloat z.2
  let lengthSecond := Random.nextFloat lengthFirst.2
  let yaw := Random.nextFloat lengthSecond.2
  let pitch := Random.nextFloat yaw.2
  let radiusFirst := Random.nextFloat pitch.2
  let radiusSecond := Random.nextFloat radiusFirst.2
  let lengthValue := Float32.mul
    (Float32.add
      (Terrain.fractionValue32 lengthFirst.1)
      (Terrain.fractionValue32 lengthSecond.1))
    200.0
  (caveSeedFromRandom dimensions state).1 = {
    start := {
      x := Float32.mul (Terrain.fractionValue32 x.1)
        (Float32.ofInt (Int.ofNat dimensions.width))
      y := Float32.mul (Terrain.fractionValue32 y.1)
        (Float32.ofInt (Int.ofNat dimensions.verticalSize))
      z := Float32.mul (Terrain.fractionValue32 z.1)
        (Float32.ofInt (Int.ofNat dimensions.depth)) }
    length := (truncateFloat32TowardZero lengthValue).toNat
    yaw := Float32.mul (Float32.mul (Terrain.fractionValue32 yaw.1) pi32) 2.0
    pitch := Float32.mul (Float32.mul (Terrain.fractionValue32 pitch.1) pi32) 2.0
    radiusFactor := Float32.mul
      (Terrain.fractionValue32 radiusFirst.1)
      (Terrain.fractionValue32 radiusSecond.1) } ∧
  (caveSeedFromRandom dimensions state).2 = radiusSecond.2

axiom caveStartDepthRange
    (dimensions : Terrain.Dimensions) (state : Random.State)
    (valid : Terrain.validDimensions dimensions) :
  0.0 ≤ Float32.toFloat (caveSeedFromRandom dimensions state).1.start.y ∧
    Float32.toFloat (caveSeedFromRandom dimensions state).1.start.y <
      Float.ofInt (Int.ofNat dimensions.verticalSize)

structure Motion32 where
  position : Point32
  yaw : Float32
  yawVelocity : Float32
  pitch : Float32
  pitchVelocity : Float32

axiom initialMotion : CaveSeed → Motion32

axiom initialMotionSemantics (seed : CaveSeed) :
  initialMotion seed = {
    position := seed.start
    yaw := seed.yaw
    yawVelocity := 0.0
    pitch := seed.pitch
    pitchVelocity := 0.0 }

axiom advancedMotion : Motion32 → Motion32

axiom advancedMotionSemantics (motion : Motion32) :
  (advancedMotion motion).position.x =
      Float32.add motion.position.x
        (Float32.mul (trajectorySine motion.yaw) (trajectoryCosine motion.pitch)) ∧
    (advancedMotion motion).position.y =
      Float32.add motion.position.y (trajectorySine motion.pitch) ∧
    (advancedMotion motion).position.z =
      Float32.add motion.position.z
        (Float32.mul (trajectoryCosine motion.yaw) (trajectoryCosine motion.pitch)) ∧
    (advancedMotion motion).yaw = motion.yaw ∧
    (advancedMotion motion).yawVelocity = motion.yawVelocity ∧
    (advancedMotion motion).pitch = motion.pitch ∧
    (advancedMotion motion).pitchVelocity = motion.pitchVelocity

structure MotionDraws where
  yawPositive : Random.Fraction
  yawNegative : Random.Fraction
  pitchPositive : Random.Fraction
  pitchNegative : Random.Fraction

axiom turnedMotion : Float32 → Motion32 → MotionDraws → Motion32

axiom turnedMotionSemantics
    (pitchDamping : Float32) (motion : Motion32) (draws : MotionDraws) :
  let pitchIntermediate := Float32.add motion.pitch
    (Float32.mul motion.pitchVelocity 0.5)
  (turnedMotion pitchDamping motion draws).position = motion.position ∧
    (turnedMotion pitchDamping motion draws).yaw =
      Float32.add motion.yaw (Float32.mul motion.yawVelocity 0.2) ∧
    (turnedMotion pitchDamping motion draws).yawVelocity =
      Float32.add
        (Float32.mul motion.yawVelocity 0.9)
        (Float32.sub
          (Terrain.fractionValue32 draws.yawPositive)
          (Terrain.fractionValue32 draws.yawNegative)) ∧
    (turnedMotion pitchDamping motion draws).pitch =
      Float32.mul pitchIntermediate 0.5 ∧
    (turnedMotion pitchDamping motion draws).pitchVelocity =
      Float32.add
        (Float32.mul motion.pitchVelocity pitchDamping)
        (Float32.sub
          (Terrain.fractionValue32 draws.pitchPositive)
          (Terrain.fractionValue32 draws.pitchNegative))

axiom caveCenter : Motion32 → Random.Fraction → Random.Fraction → Random.Fraction → Point32

axiom caveCenterSemantics
    (motion : Motion32)
    (xDraw yDraw zDraw : Random.Fraction) :
  caveCenter motion xDraw yDraw zDraw = {
    x := Float32.add motion.position.x
      (Float32.mul
        (Float32.sub (Float32.mul (Terrain.fractionValue32 xDraw) 4.0) 2.0)
        0.2)
    y := Float32.add motion.position.y
      (Float32.mul
        (Float32.sub (Float32.mul (Terrain.fractionValue32 yDraw) 4.0) 2.0)
        0.2)
    z := Float32.add motion.position.z
      (Float32.mul
        (Float32.sub (Float32.mul (Terrain.fractionValue32 zDraw) 4.0) 2.0)
        0.2) }

opaque caveRadius : Terrain.Dimensions → CaveSeed → Nat → Point32 → Float32

axiom caveRadiusSemantics
    (dimensions : Terrain.Dimensions) (seed : CaveSeed) (step : Nat) (center : Point32) :
  let height := Float32.ofInt (Int.ofNat dimensions.verticalSize)
  let vertical := Float32.div (Float32.sub height center.y) height
  let depthScale := Float32.add (Float32.mul vertical 3.5) 1.0
  let maximum := Float32.add 1.2 (Float32.mul depthScale seed.radiusFactor)
  let phase := Float32.div
    (Float32.mul (Float32.ofInt (Int.ofNat step)) pi32)
    (Float32.ofInt (Int.ofNat seed.length))
  caveRadius dimensions seed step center =
    Float32.mul (trajectorySine phase) maximum

opaque ellipsoidMetric : Point32 → Terrain.Position → Float32

axiom ellipsoidMetricSemantics (center : Point32) (position : Terrain.Position) :
  let dx := Float32.sub (Float32.ofInt (Int.ofNat position.x)) center.x
  let dy := Float32.sub (Float32.ofInt (Int.ofNat position.y)) center.y
  let dz := Float32.sub (Float32.ofInt (Int.ofNat position.z)) center.z
  ellipsoidMetric center position =
    Float32.add
      (Float32.add (Float32.mul dx dx)
        (Float32.mul (Float32.mul dy dy) 2.0))
      (Float32.mul dz dz)

axiom interiorPosition : Terrain.Dimensions → Terrain.Position → Prop

axiom interiorPositionSemantics
    (dimensions : Terrain.Dimensions) (position : Terrain.Position) :
  interiorPosition dimensions position ↔
    1 ≤ position.x ∧ position.x < dimensions.width - 1 ∧
    1 ≤ position.y ∧ position.y < dimensions.verticalSize - 1 ∧
    1 ≤ position.z ∧ position.z < dimensions.depth - 1

axiom insideEllipsoid :
  Terrain.Dimensions → Point32 → Float32 → Terrain.Position → Prop

axiom insideEllipsoidSemantics
    (dimensions : Terrain.Dimensions) (center : Point32) (radius : Float32)
    (position : Terrain.Position) :
  insideEllipsoid dimensions center radius position ↔
    interiorPosition dimensions position ∧
    Float32.toFloat (ellipsoidMetric center position) <
      Float32.toFloat (Float32.mul radius radius)

axiom replaceStoneEllipsoid :
  Terrain.Dimensions → Terrain.BlockField → Point32 → Float32 → Nat → Terrain.BlockField

axiom replaceStoneEllipsoidInside
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (center : Point32) (radius : Float32) (material : Nat)
    (position : Terrain.Position)
    (inside : insideEllipsoid dimensions center radius position)
    (stone : Terrain.blockAt field position.x position.y position.z = Terrain.stoneId) :
  Terrain.blockAt (replaceStoneEllipsoid dimensions field center radius material)
    position.x position.y position.z = material

axiom replaceStoneEllipsoidUnchanged
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (center : Point32) (radius : Float32) (material : Nat)
    (position : Terrain.Position)
    (unchanged : ¬ insideEllipsoid dimensions center radius position ∨
      Terrain.blockAt field position.x position.y position.z ≠ Terrain.stoneId) :
  Terrain.blockAt (replaceStoneEllipsoid dimensions field center radius material)
    position.x position.y position.z =
      Terrain.blockAt field position.x position.y position.z

structure CaveStepResult where
  state : Random.State
  field : Terrain.BlockField
  motion : Motion32

axiom caveStep :
  Terrain.Dimensions → CaveSeed → Nat → Random.State →
    Terrain.BlockField → Motion32 → CaveStepResult

axiom caveStepSemantics
    (dimensions : Terrain.Dimensions) (seed : CaveSeed) (step : Nat)
    (state : Random.State) (field : Terrain.BlockField) (motion : Motion32) :
  let yawPositive := Random.nextFloat state
  let yawNegative := Random.nextFloat yawPositive.2
  let pitchPositive := Random.nextFloat yawNegative.2
  let pitchNegative := Random.nextFloat pitchPositive.2
  let decision := Random.nextFloat pitchNegative.2
  let moved := advancedMotion motion
  let turned := turnedMotion 0.75 moved {
    yawPositive := yawPositive.1
    yawNegative := yawNegative.1
    pitchPositive := pitchPositive.1
    pitchNegative := pitchNegative.1 }
  if Float32.toFloat (Terrain.fractionValue32 decision.1) < 0.25 then
    caveStep dimensions seed step state field motion = {
      state := decision.2, field := field, motion := turned }
  else
    let xDraw := Random.nextFloat decision.2
    let yDraw := Random.nextFloat xDraw.2
    let zDraw := Random.nextFloat yDraw.2
    let center := caveCenter moved xDraw.1 yDraw.1 zDraw.1
    let radius := caveRadius dimensions seed step center
    caveStep dimensions seed step state field motion = {
      state := zDraw.2
      field := replaceStoneEllipsoid dimensions field center radius Terrain.airId
      motion := turned }

inductive CaveRun :
    Nat → Nat → Terrain.Dimensions → CaveSeed → Random.State → Terrain.BlockField →
      Motion32 → Random.State → Terrain.BlockField → Prop where
  | done
      (nextStep : Nat)
      (dimensions : Terrain.Dimensions) (seed : CaveSeed)
      (state : Random.State) (field : Terrain.BlockField) (motion : Motion32) :
      CaveRun 0 nextStep dimensions seed state field motion state field
  | step
      (remaining nextStep : Nat) (dimensions : Terrain.Dimensions) (seed : CaveSeed)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (motion : Motion32)
      (rest : CaveRun remaining (nextStep + 1) dimensions seed
        (caveStep dimensions seed nextStep state field motion).state
        (caveStep dimensions seed nextStep state field motion).field
        (caveStep dimensions seed nextStep state field motion).motion
        finalState finalField) :
      CaveRun (remaining + 1) nextStep dimensions seed
        state field motion finalState finalField

inductive CavePlacement :
    Nat → Terrain.Dimensions → Random.State → Terrain.BlockField →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField) :
      CavePlacement 0 dimensions state field state field
  | step
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (run : CaveRun
        (caveSeedFromRandom dimensions state).1.length 0 dimensions
        (caveSeedFromRandom dimensions state).1
        (caveSeedFromRandom dimensions state).2 field
        (initialMotion (caveSeedFromRandom dimensions state).1)
        finalState finalField) :
      CavePlacement (remaining + 1) dimensions state field finalState finalField

axiom cavePass :
  Terrain.Dimensions → Random.State → Terrain.BlockField → Random.State × Terrain.BlockField

axiom cavePassSemantics
    (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField) :
  CavePlacement (caveAttemptCount dimensions) dimensions state field
    (cavePass dimensions state field).1 (cavePass dimensions state field).2

axiom cavePassOnlyRemovesStone
    (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField)
    (position : Terrain.Position) :
  Terrain.blockAt (cavePass dimensions state field).2
      position.x position.y position.z =
      Terrain.blockAt field position.x position.y position.z ∨
    (Terrain.blockAt field position.x position.y position.z = Terrain.stoneId ∧
      Terrain.blockAt (cavePass dimensions state field).2
        position.x position.y position.z = Terrain.airId)

theorem cavesCarveOnlyStoneToAir
    (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField)
    (position : Terrain.Position) :
  Terrain.blockAt (cavePass dimensions state field).2
      position.x position.y position.z =
      Terrain.blockAt field position.x position.y position.z ∨
    (Terrain.blockAt field position.x position.y position.z = Terrain.stoneId ∧
      Terrain.blockAt (cavePass dimensions state field).2
        position.x position.y position.z = Terrain.airId) :=
  cavePassOnlyRemovesStone dimensions state field position

end Spec.Carve
