import Spec.Carve

namespace Spec.Ore

inductive ResourceKind where
  | coal
  | iron
  | gold

opaque resourceMaterial : ResourceKind → Nat

axiom coalMaterial : resourceMaterial ResourceKind.coal = 16

axiom ironMaterial : resourceMaterial ResourceKind.iron = 15

axiom goldMaterial : resourceMaterial ResourceKind.gold = 14

opaque resourceAbundance : ResourceKind → Nat

axiom coalAbundance : resourceAbundance ResourceKind.coal = 90

axiom ironAbundance : resourceAbundance ResourceKind.iron = 70

axiom goldAbundance : resourceAbundance ResourceKind.gold = 50

opaque veinAttemptCount : Terrain.Dimensions → ResourceKind → Nat

axiom veinAttemptCountSemantics
    (dimensions : Terrain.Dimensions) (kind : ResourceKind) :
  veinAttemptCount dimensions kind =
    ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) *
      resourceAbundance kind / 100

theorem coalVeinCount (dimensions : Terrain.Dimensions) :
    veinAttemptCount dimensions ResourceKind.coal =
      ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) * 90 / 100 := by
  rw [veinAttemptCountSemantics, coalAbundance]

theorem ironVeinCount (dimensions : Terrain.Dimensions) :
    veinAttemptCount dimensions ResourceKind.iron =
      ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) * 70 / 100 := by
  rw [veinAttemptCountSemantics, ironAbundance]

theorem goldVeinCount (dimensions : Terrain.Dimensions) :
    veinAttemptCount dimensions ResourceKind.gold =
      ((dimensions.width * dimensions.depth * dimensions.verticalSize / 256) / 64) * 50 / 100 := by
  rw [veinAttemptCountSemantics, goldAbundance]

structure VeinSeed where
  start : Carve.Point32
  length : Nat
  yaw : Float32
  pitch : Float32

axiom veinSeedFromRandom :
  Terrain.Dimensions → ResourceKind → Random.State → VeinSeed × Random.State

axiom veinSeedFromRandomSemantics
    (dimensions : Terrain.Dimensions) (kind : ResourceKind) (state : Random.State) :
  let x := Random.nextFloat state
  let y := Random.nextFloat x.2
  let z := Random.nextFloat y.2
  let lengthFirst := Random.nextFloat z.2
  let lengthSecond := Random.nextFloat lengthFirst.2
  let yaw := Random.nextFloat lengthSecond.2
  let pitch := Random.nextFloat yaw.2
  let lengthValue := Float32.div
    (Float32.mul
      (Float32.mul
        (Float32.add
          (Terrain.fractionValue32 lengthFirst.1)
          (Terrain.fractionValue32 lengthSecond.1))
        75.0)
      (Float32.ofInt (Int.ofNat (resourceAbundance kind))))
    100.0
  (veinSeedFromRandom dimensions kind state).1 = {
    start := {
      x := Float32.mul (Terrain.fractionValue32 x.1)
        (Float32.ofInt (Int.ofNat dimensions.width))
      y := Float32.mul (Terrain.fractionValue32 y.1)
        (Float32.ofInt (Int.ofNat dimensions.verticalSize))
      z := Float32.mul (Terrain.fractionValue32 z.1)
        (Float32.ofInt (Int.ofNat dimensions.depth)) }
    length := (Carve.truncateFloat32TowardZero lengthValue).toNat
    yaw := Float32.mul
      (Float32.mul (Terrain.fractionValue32 yaw.1) Carve.pi32) 2.0
    pitch := Float32.mul
      (Float32.mul (Terrain.fractionValue32 pitch.1) Carve.pi32) 2.0 } ∧
  (veinSeedFromRandom dimensions kind state).2 = pitch.2

axiom veinStartDepthRange
    (dimensions : Terrain.Dimensions) (kind : ResourceKind) (state : Random.State)
    (valid : Terrain.validDimensions dimensions) :
  0.0 ≤ Float32.toFloat (veinSeedFromRandom dimensions kind state).1.start.y ∧
    Float32.toFloat (veinSeedFromRandom dimensions kind state).1.start.y <
      Float.ofInt (Int.ofNat dimensions.verticalSize)

theorem everyResourceUsesTheFullStartingDepthRange
    (dimensions : Terrain.Dimensions) (kind : ResourceKind) (state : Random.State)
    (valid : Terrain.validDimensions dimensions) :
  0.0 ≤ Float32.toFloat (veinSeedFromRandom dimensions kind state).1.start.y ∧
    Float32.toFloat (veinSeedFromRandom dimensions kind state).1.start.y <
      Float.ofInt (Int.ofNat dimensions.verticalSize) :=
  veinStartDepthRange dimensions kind state valid

axiom initialVeinMotion : VeinSeed → Carve.Motion32

axiom initialVeinMotionSemantics (seed : VeinSeed) :
  initialVeinMotion seed = {
    position := seed.start
    yaw := seed.yaw
    yawVelocity := 0.0
    pitch := seed.pitch
    pitchVelocity := 0.0 }

opaque veinRadius : ResourceKind → VeinSeed → Nat → Float32

axiom veinRadiusSemantics (kind : ResourceKind) (seed : VeinSeed) (step : Nat) :
  let phase := Float32.div
    (Float32.mul (Float32.ofInt (Int.ofNat step)) Carve.pi32)
    (Float32.ofInt (Int.ofNat seed.length))
  veinRadius kind seed step = Float32.add
    (Float32.div
      (Float32.mul
        (Carve.trajectorySine phase)
        (Float32.ofInt (Int.ofNat (resourceAbundance kind))))
      100.0)
    1.0

structure VeinStepResult where
  state : Random.State
  field : Terrain.BlockField
  motion : Carve.Motion32

axiom veinStep :
  Terrain.Dimensions → ResourceKind → VeinSeed → Nat → Random.State →
    Terrain.BlockField → Carve.Motion32 → VeinStepResult

axiom veinStepSemantics
    (dimensions : Terrain.Dimensions) (kind : ResourceKind) (seed : VeinSeed)
    (step : Nat) (state : Random.State) (field : Terrain.BlockField)
    (motion : Carve.Motion32) :
  let yawPositive := Random.nextFloat state
  let yawNegative := Random.nextFloat yawPositive.2
  let pitchPositive := Random.nextFloat yawNegative.2
  let pitchNegative := Random.nextFloat pitchPositive.2
  let moved := Carve.advancedMotion motion
  let turned := Carve.turnedMotion 0.9 moved {
    yawPositive := yawPositive.1
    yawNegative := yawNegative.1
    pitchPositive := pitchPositive.1
    pitchNegative := pitchNegative.1 }
  veinStep dimensions kind seed step state field motion = {
    state := pitchNegative.2
    field := Carve.replaceStoneEllipsoid dimensions field moved.position
      (veinRadius kind seed step) (resourceMaterial kind)
    motion := turned }

inductive VeinRun :
    Nat → Nat → Terrain.Dimensions → ResourceKind → VeinSeed → Random.State →
      Terrain.BlockField → Carve.Motion32 → Random.State → Terrain.BlockField → Prop where
  | done
      (nextStep : Nat)
      (dimensions : Terrain.Dimensions) (kind : ResourceKind) (seed : VeinSeed)
      (state : Random.State) (field : Terrain.BlockField) (motion : Carve.Motion32) :
      VeinRun 0 nextStep dimensions kind seed state field motion state field
  | step
      (remaining nextStep : Nat) (dimensions : Terrain.Dimensions)
      (kind : ResourceKind) (seed : VeinSeed)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (motion : Carve.Motion32)
      (rest : VeinRun remaining (nextStep + 1) dimensions kind seed
        (veinStep dimensions kind seed nextStep state field motion).state
        (veinStep dimensions kind seed nextStep state field motion).field
        (veinStep dimensions kind seed nextStep state field motion).motion
        finalState finalField) :
      VeinRun (remaining + 1) nextStep dimensions kind seed
        state field motion finalState finalField

inductive ResourcePlacement :
    Nat → Terrain.Dimensions → ResourceKind → Random.State → Terrain.BlockField →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (kind : ResourceKind)
      (state : Random.State) (field : Terrain.BlockField) :
      ResourcePlacement 0 dimensions kind state field state field
  | step
      (remaining : Nat) (dimensions : Terrain.Dimensions) (kind : ResourceKind)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (run : VeinRun
        (veinSeedFromRandom dimensions kind state).1.length 0 dimensions kind
        (veinSeedFromRandom dimensions kind state).1
        (veinSeedFromRandom dimensions kind state).2 field
        (initialVeinMotion (veinSeedFromRandom dimensions kind state).1)
        finalState finalField) :
      ResourcePlacement (remaining + 1) dimensions kind state field finalState finalField

axiom resourcePass :
  Terrain.Dimensions → ResourceKind → Random.State → Terrain.BlockField →
    Random.State × Terrain.BlockField

axiom resourcePassSemantics
    (dimensions : Terrain.Dimensions) (kind : ResourceKind)
    (state : Random.State) (field : Terrain.BlockField) :
  ResourcePlacement (veinAttemptCount dimensions kind) dimensions kind state field
    (resourcePass dimensions kind state field).1
    (resourcePass dimensions kind state field).2

axiom allResourcePasses :
  Terrain.Dimensions → Random.State → Terrain.BlockField → Random.State × Terrain.BlockField

axiom allResourcePassesSemantics
    (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField) :
  let coal := resourcePass dimensions ResourceKind.coal state field
  let iron := resourcePass dimensions ResourceKind.iron coal.1 coal.2
  let gold := resourcePass dimensions ResourceKind.gold iron.1 iron.2
  allResourcePasses dimensions state field = gold

axiom carvingAndResources :
  Terrain.Dimensions → Random.State → Terrain.BlockField → Random.State × Terrain.BlockField

axiom carvingAndResourcesSemantics
    (dimensions : Terrain.Dimensions) (state : Random.State) (field : Terrain.BlockField) :
  let caves := Carve.cavePass dimensions state field
  carvingAndResources dimensions state field =
    allResourcePasses dimensions caves.1 caves.2

axiom resourcePassOnlyReplacesStone
    (dimensions : Terrain.Dimensions) (kind : ResourceKind)
    (state : Random.State) (field : Terrain.BlockField) (position : Terrain.Position) :
  Terrain.blockAt (resourcePass dimensions kind state field).2
      position.x position.y position.z =
      Terrain.blockAt field position.x position.y position.z ∨
    (Terrain.blockAt field position.x position.y position.z = Terrain.stoneId ∧
      Terrain.blockAt (resourcePass dimensions kind state field).2
        position.x position.y position.z = resourceMaterial kind)

theorem veinsReplaceOnlyStone
    (dimensions : Terrain.Dimensions) (kind : ResourceKind)
    (state : Random.State) (field : Terrain.BlockField) (position : Terrain.Position) :
  Terrain.blockAt (resourcePass dimensions kind state field).2
      position.x position.y position.z =
      Terrain.blockAt field position.x position.y position.z ∨
    (Terrain.blockAt field position.x position.y position.z = Terrain.stoneId ∧
      Terrain.blockAt (resourcePass dimensions kind state field).2
        position.x position.y position.z = resourceMaterial kind) :=
  resourcePassOnlyReplacesStone dimensions kind state field position

axiom sandPatch :
  Terrain.Dimensions → Terrain.ElevationNoise → Terrain.SurfaceNoise →
    Terrain.BlockField → Terrain.Position → Prop

axiom sandPatchSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position) :
  sandPatch dimensions elevation surface field position ↔
    position.y = Terrain.surfaceHeight dimensions elevation position.x position.z ∧
    Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.airId ∧
    position.y ≤ dimensions.verticalSize / 2 - 1 ∧
    8.0 < Noise.octaveValue surface.sand
      (Float.ofInt (Int.ofNat position.x)) (Float.ofInt (Int.ofNat position.z))

axiom gravelPatch :
  Terrain.Dimensions → Terrain.ElevationNoise → Terrain.SurfaceNoise →
    Terrain.BlockField → Terrain.Position → Prop

axiom gravelPatchSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position) :
  gravelPatch dimensions elevation surface field position ↔
    position.y = Terrain.surfaceHeight dimensions elevation position.x position.z ∧
    (Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.flowingWaterId ∨
      Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.stillWaterId) ∧
    position.y ≤ dimensions.verticalSize / 2 - 1 ∧
    12.0 < Noise.octaveValue surface.gravel
      (Float.ofInt (Int.ofNat position.x)) (Float.ofInt (Int.ofNat position.z))

axiom sandPatchMaterial
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position)
    (xBound : position.x < dimensions.width)
    (zBound : position.z < dimensions.depth)
    (member : sandPatch dimensions elevation surface field position) :
  Terrain.blockAt (Terrain.surfacedTerrain dimensions elevation surface field)
    position.x position.y position.z = Terrain.sandId

axiom gravelPatchMaterial
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position)
    (xBound : position.x < dimensions.width)
    (zBound : position.z < dimensions.depth)
    (member : gravelPatch dimensions elevation surface field position) :
  Terrain.blockAt (Terrain.surfacedTerrain dimensions elevation surface field)
    position.x position.y position.z = Terrain.gravelId

theorem sandPatchesAreDryExposedSurfaceCells
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position)
    (member : sandPatch dimensions elevation surface field position) :
  position.y = Terrain.surfaceHeight dimensions elevation position.x position.z ∧
    Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.airId := by
  exact ⟨(sandPatchSemantics dimensions elevation surface field position).mp member |>.1,
    (sandPatchSemantics dimensions elevation surface field position).mp member |>.2.1⟩

theorem gravelPatchesAreSubmergedSurfaceCells
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (surface : Terrain.SurfaceNoise) (field : Terrain.BlockField)
    (position : Terrain.Position)
    (member : gravelPatch dimensions elevation surface field position) :
  position.y = Terrain.surfaceHeight dimensions elevation position.x position.z ∧
    (Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.flowingWaterId ∨
      Terrain.blockAt field position.x (position.y + 1) position.z = Terrain.stillWaterId) := by
  exact ⟨(gravelPatchSemantics dimensions elevation surface field position).mp member |>.1,
    (gravelPatchSemantics dimensions elevation surface field position).mp member |>.2.1⟩

end Spec.Ore
