import Spec.Ore

namespace Spec.Level

opaque firstFlowerId : Nat
opaque secondFlowerId : Nat
opaque firstMushroomId : Nat
opaque secondMushroomId : Nat
opaque trunkId : Nat
opaque foliageId : Nat

axiom firstFlowerIdValue : firstFlowerId = 37
axiom secondFlowerIdValue : secondFlowerId = 38
axiom firstMushroomIdValue : firstMushroomId = 39
axiom secondMushroomIdValue : secondMushroomId = 40
axiom trunkIdValue : trunkId = 17
axiom foliageIdValue : foliageId = 18

inductive FlowerKind where
  | first
  | second

inductive MushroomKind where
  | first
  | second

opaque flowerMaterial : FlowerKind → Nat

axiom firstFlowerMaterial : flowerMaterial FlowerKind.first = firstFlowerId

axiom secondFlowerMaterial : flowerMaterial FlowerKind.second = secondFlowerId

opaque mushroomMaterial : MushroomKind → Nat

axiom firstMushroomMaterial : mushroomMaterial MushroomKind.first = firstMushroomId

axiom secondMushroomMaterial : mushroomMaterial MushroomKind.second = secondMushroomId

axiom flowerKindFromIndex : Nat → FlowerKind

axiom flowerKindZero : flowerKindFromIndex 0 = FlowerKind.first

axiom flowerKindOne : flowerKindFromIndex 1 = FlowerKind.second

axiom mushroomKindFromIndex : Nat → MushroomKind

axiom mushroomKindZero : mushroomKindFromIndex 0 = MushroomKind.first

axiom mushroomKindOne : mushroomKindFromIndex 1 = MushroomKind.second

structure HorizontalWalkPoint where
  x : Int
  z : Int

structure SubterraneanWalkPoint where
  x : Int
  y : Int
  z : Int

opaque flowerEligible :
  Terrain.Dimensions → Terrain.ElevationNoise → Terrain.BlockField →
    HorizontalWalkPoint → Prop

axiom flowerEligibleSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (field : Terrain.BlockField) (point : HorizontalWalkPoint) :
  flowerEligible dimensions elevation field point ↔
    0 ≤ point.x ∧ point.x.toNat < dimensions.width ∧
    0 ≤ point.z ∧ point.z.toNat < dimensions.depth ∧
    Terrain.blockAt field point.x.toNat
      (Terrain.surfaceHeight dimensions elevation point.x.toNat point.z.toNat + 1)
      point.z.toNat = Terrain.airId ∧
    Terrain.blockAt field point.x.toNat
      (Terrain.surfaceHeight dimensions elevation point.x.toNat point.z.toNat)
      point.z.toNat = Terrain.grassId

axiom placeFlower :
  Terrain.Dimensions → Terrain.ElevationNoise → FlowerKind →
    Terrain.BlockField → HorizontalWalkPoint → Terrain.BlockField

axiom placeFlowerEligible
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : FlowerKind) (field : Terrain.BlockField) (point : HorizontalWalkPoint)
    (eligible : flowerEligible dimensions elevation field point) :
  Terrain.blockAt (placeFlower dimensions elevation kind field point)
      point.x.toNat
      (Terrain.surfaceHeight dimensions elevation point.x.toNat point.z.toNat + 1)
      point.z.toNat = flowerMaterial kind

axiom placeFlowerUnchanged
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : FlowerKind) (field : Terrain.BlockField) (point : HorizontalWalkPoint)
    (position : Terrain.Position)
    (unchanged : ¬ flowerEligible dimensions elevation field point ∨
      position.x ≠ point.x.toNat ∨ position.z ≠ point.z.toNat ∨
      position.y ≠ Terrain.surfaceHeight dimensions elevation
        point.x.toNat point.z.toNat + 1) :
  Terrain.blockAt (placeFlower dimensions elevation kind field point)
      position.x position.y position.z =
    Terrain.blockAt field position.x position.y position.z

structure FlowerStepResult where
  state : Random.State
  field : Terrain.BlockField
  point : HorizontalWalkPoint

axiom flowerStep :
  Terrain.Dimensions → Terrain.ElevationNoise → FlowerKind → Random.State →
    Terrain.BlockField → HorizontalWalkPoint → FlowerStepResult

axiom flowerStepSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : FlowerKind) (state : Random.State) (field : Terrain.BlockField)
    (point : HorizontalWalkPoint) :
  let xPositive := Random.nextIntBounded state 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let zPositive := Random.nextIntBounded xNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  let nextPoint : HorizontalWalkPoint := {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }
  flowerStep dimensions elevation kind state field point = {
    state := zNegative.2
    field := placeFlower dimensions elevation kind field nextPoint
    point := nextPoint }

inductive FlowerWalk :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → FlowerKind →
      Random.State → Terrain.BlockField → HorizontalWalkPoint →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (kind : FlowerKind) (state : Random.State) (field : Terrain.BlockField)
      (point : HorizontalWalkPoint) :
      FlowerWalk 0 dimensions elevation kind state field point state field
  | step
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise) (kind : FlowerKind)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (point : HorizontalWalkPoint)
      (rest : FlowerWalk remaining dimensions elevation kind
        (flowerStep dimensions elevation kind state field point).state
        (flowerStep dimensions elevation kind state field point).field
        (flowerStep dimensions elevation kind state field point).point
        finalState finalField) :
      FlowerWalk (remaining + 1) dimensions elevation kind state field point
        finalState finalField

inductive FlowerCluster :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → FlowerKind →
      HorizontalWalkPoint → Random.State → Terrain.BlockField →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (kind : FlowerKind) (origin : HorizontalWalkPoint)
      (state : Random.State) (field : Terrain.BlockField) :
      FlowerCluster 0 dimensions elevation kind origin state field state field
  | walk
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise) (kind : FlowerKind)
      (origin : HorizontalWalkPoint)
      (state walkState finalState : Random.State)
      (field walkField finalField : Terrain.BlockField)
      (oneWalk : FlowerWalk 5 dimensions elevation kind state field origin
        walkState walkField)
      (rest : FlowerCluster remaining dimensions elevation kind origin
        walkState walkField finalState finalField) :
      FlowerCluster (remaining + 1) dimensions elevation kind origin state field
        finalState finalField

opaque flowerAttemptCount : Terrain.Dimensions → Nat

axiom flowerAttemptCountSemantics (dimensions : Terrain.Dimensions) :
  flowerAttemptCount dimensions = dimensions.width * dimensions.depth / 3000

inductive FlowerPlacement :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → Random.State →
      Terrain.BlockField → Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (state : Random.State) (field : Terrain.BlockField) :
      FlowerPlacement 0 dimensions elevation state field state field
  | cluster
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise)
      (state kindState xState zState clusterState finalState : Random.State)
      (field clusterField finalField : Terrain.BlockField)
      (kindIndex x z : Nat)
      (kindDraw : Random.nextIntBounded state 2 = (kindIndex, kindState))
      (xDraw : Random.nextIntBounded kindState dimensions.width = (x, xState))
      (zDraw : Random.nextIntBounded xState dimensions.depth = (z, zState))
      (oneCluster : FlowerCluster 10 dimensions elevation
        (flowerKindFromIndex kindIndex)
        { x := Int.ofNat x, z := Int.ofNat z }
        zState field clusterState clusterField)
      (rest : FlowerPlacement remaining dimensions elevation
        clusterState clusterField finalState finalField) :
      FlowerPlacement (remaining + 1) dimensions elevation state field
        finalState finalField

axiom flowerPass :
  Terrain.Dimensions → Terrain.ElevationNoise → Random.State →
    Terrain.BlockField → Random.State × Terrain.BlockField

axiom flowerPassSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (state : Random.State) (field : Terrain.BlockField) :
  FlowerPlacement (flowerAttemptCount dimensions) dimensions elevation state field
    (flowerPass dimensions elevation state field).1
    (flowerPass dimensions elevation state field).2

opaque mushroomEligible :
  Terrain.Dimensions → Terrain.ElevationNoise → Terrain.BlockField →
    SubterraneanWalkPoint → Prop

axiom mushroomEligibleSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (field : Terrain.BlockField) (point : SubterraneanWalkPoint) :
  mushroomEligible dimensions elevation field point ↔
    0 ≤ point.x ∧ point.x.toNat < dimensions.width ∧
    1 ≤ point.y ∧
    point.y.toNat < Terrain.surfaceHeight dimensions elevation
      point.x.toNat point.z.toNat - 1 ∧
    0 ≤ point.z ∧ point.z.toNat < dimensions.depth ∧
    Terrain.blockAt field point.x.toNat point.y.toNat point.z.toNat = Terrain.airId ∧
    Terrain.blockAt field point.x.toNat (point.y.toNat - 1) point.z.toNat =
      Terrain.stoneId

axiom placeMushroom :
  Terrain.Dimensions → Terrain.ElevationNoise → MushroomKind →
    Terrain.BlockField → SubterraneanWalkPoint → Terrain.BlockField

axiom placeMushroomEligible
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : MushroomKind) (field : Terrain.BlockField)
    (point : SubterraneanWalkPoint)
    (eligible : mushroomEligible dimensions elevation field point) :
  Terrain.blockAt (placeMushroom dimensions elevation kind field point)
    point.x.toNat point.y.toNat point.z.toNat = mushroomMaterial kind

axiom placeMushroomUnchanged
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : MushroomKind) (field : Terrain.BlockField)
    (point : SubterraneanWalkPoint) (position : Terrain.Position)
    (unchanged : ¬ mushroomEligible dimensions elevation field point ∨
      position.x ≠ point.x.toNat ∨ position.y ≠ point.y.toNat ∨
      position.z ≠ point.z.toNat) :
  Terrain.blockAt (placeMushroom dimensions elevation kind field point)
      position.x position.y position.z =
    Terrain.blockAt field position.x position.y position.z

structure MushroomStepResult where
  state : Random.State
  field : Terrain.BlockField
  point : SubterraneanWalkPoint

axiom mushroomStep :
  Terrain.Dimensions → Terrain.ElevationNoise → MushroomKind → Random.State →
    Terrain.BlockField → SubterraneanWalkPoint → MushroomStepResult

axiom mushroomStepSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (kind : MushroomKind) (state : Random.State) (field : Terrain.BlockField)
    (point : SubterraneanWalkPoint) :
  let xPositive := Random.nextIntBounded state 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let yPositive := Random.nextIntBounded xNegative.2 2
  let yNegative := Random.nextIntBounded yPositive.2 2
  let zPositive := Random.nextIntBounded yNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  let nextPoint : SubterraneanWalkPoint := {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    y := point.y + Int.ofNat yPositive.1 - Int.ofNat yNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }
  mushroomStep dimensions elevation kind state field point = {
    state := zNegative.2
    field := placeMushroom dimensions elevation kind field nextPoint
    point := nextPoint }

inductive MushroomWalk :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → MushroomKind →
      Random.State → Terrain.BlockField → SubterraneanWalkPoint →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (kind : MushroomKind) (state : Random.State) (field : Terrain.BlockField)
      (point : SubterraneanWalkPoint) :
      MushroomWalk 0 dimensions elevation kind state field point state field
  | step
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise) (kind : MushroomKind)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (point : SubterraneanWalkPoint)
      (rest : MushroomWalk remaining dimensions elevation kind
        (mushroomStep dimensions elevation kind state field point).state
        (mushroomStep dimensions elevation kind state field point).field
        (mushroomStep dimensions elevation kind state field point).point
        finalState finalField) :
      MushroomWalk (remaining + 1) dimensions elevation kind state field point
        finalState finalField

inductive MushroomCluster :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → MushroomKind →
      SubterraneanWalkPoint → Random.State → Terrain.BlockField →
      Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (kind : MushroomKind) (origin : SubterraneanWalkPoint)
      (state : Random.State) (field : Terrain.BlockField) :
      MushroomCluster 0 dimensions elevation kind origin state field state field
  | walk
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise) (kind : MushroomKind)
      (origin : SubterraneanWalkPoint)
      (state walkState finalState : Random.State)
      (field walkField finalField : Terrain.BlockField)
      (oneWalk : MushroomWalk 5 dimensions elevation kind state field origin
        walkState walkField)
      (rest : MushroomCluster remaining dimensions elevation kind origin
        walkState walkField finalState finalField) :
      MushroomCluster (remaining + 1) dimensions elevation kind origin state field
        finalState finalField

opaque mushroomAttemptCount : Terrain.Dimensions → Nat

axiom mushroomAttemptCountSemantics (dimensions : Terrain.Dimensions) :
  mushroomAttemptCount dimensions =
    dimensions.width * dimensions.depth * dimensions.verticalSize / 2000

inductive MushroomPlacement :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → Random.State →
      Terrain.BlockField → Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (state : Random.State) (field : Terrain.BlockField) :
      MushroomPlacement 0 dimensions elevation state field state field
  | cluster
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise)
      (state kindState xState yState zState clusterState finalState : Random.State)
      (field clusterField finalField : Terrain.BlockField)
      (kindIndex x y z : Nat)
      (kindDraw : Random.nextIntBounded state 2 = (kindIndex, kindState))
      (xDraw : Random.nextIntBounded kindState dimensions.width = (x, xState))
      (yDraw : Random.nextIntBounded xState dimensions.verticalSize = (y, yState))
      (zDraw : Random.nextIntBounded yState dimensions.depth = (z, zState))
      (oneCluster : MushroomCluster 20 dimensions elevation
        (mushroomKindFromIndex kindIndex)
        { x := Int.ofNat x, y := Int.ofNat y, z := Int.ofNat z }
        zState field clusterState clusterField)
      (rest : MushroomPlacement remaining dimensions elevation
        clusterState clusterField finalState finalField) :
      MushroomPlacement (remaining + 1) dimensions elevation state field
        finalState finalField

axiom mushroomPass :
  Terrain.Dimensions → Terrain.ElevationNoise → Random.State →
    Terrain.BlockField → Random.State × Terrain.BlockField

axiom mushroomPassSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (state : Random.State) (field : Terrain.BlockField) :
  MushroomPlacement (mushroomAttemptCount dimensions) dimensions elevation state field
    (mushroomPass dimensions elevation state field).1
    (mushroomPass dimensions elevation state field).2

opaque horizontalDistance : Nat → Nat → Nat

axiom horizontalDistanceSemantics (left right : Nat) :
  horizontalDistance left right = if left ≤ right then right - left else left - right

opaque treeClearanceRadius : Terrain.Position → Nat → Nat → Nat

axiom treeClearanceRadiusBase
    (base : Terrain.Position) (height : Nat) (heightRange : 4 ≤ height) :
  treeClearanceRadius base height base.y = 0

axiom treeClearanceRadiusMiddle
    (base : Terrain.Position) (height y : Nat)
    (heightRange : 4 ≤ height)
    (aboveBase : base.y < y) (belowCrown : y < base.y + height - 1) :
  treeClearanceRadius base height y = 1

axiom treeClearanceRadiusCrown
    (base : Terrain.Position) (height y : Nat)
    (heightRange : 4 ≤ height)
    (crown : base.y + height - 1 ≤ y) :
  treeClearanceRadius base height y = 2

opaque treeClearance :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Nat → Prop

axiom treeClearanceSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (base : Terrain.Position) (height : Nat) :
  treeClearance dimensions field base height ↔
    2 ≤ base.x ∧ base.x + 2 < dimensions.width ∧
    2 ≤ base.z ∧ base.z + 2 < dimensions.depth ∧
    base.y + height + 1 < dimensions.verticalSize ∧
    ∀ position : Terrain.Position,
      base.y ≤ position.y → position.y ≤ base.y + height + 1 →
      horizontalDistance base.x position.x ≤
        treeClearanceRadius base height position.y →
      horizontalDistance base.z position.z ≤
        treeClearanceRadius base height position.y →
      Terrain.inside dimensions position ∧
        Terrain.blockAt field position.x position.y position.z = Terrain.airId

opaque treeEligible :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Nat → Prop

axiom treeEligibleSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (base : Terrain.Position) (height : Nat) :
  treeEligible dimensions field base height ↔
    treeClearance dimensions field base height ∧
    0 < base.y ∧
    Terrain.blockAt field base.x (base.y - 1) base.z = Terrain.grassId

axiom overwriteBlock :
  Terrain.BlockField → Terrain.Position → Nat → Terrain.BlockField

axiom overwriteBlockAt
    (field : Terrain.BlockField) (position : Terrain.Position) (material : Nat) :
  Terrain.blockAt (overwriteBlock field position material)
    position.x position.y position.z = material

axiom overwriteBlockAway
    (field : Terrain.BlockField) (position other : Terrain.Position) (material : Nat)
    (different : other.x ≠ position.x ∨ other.y ≠ position.y ∨ other.z ≠ position.z) :
  Terrain.blockAt (overwriteBlock field position material)
      other.x other.y other.z = Terrain.blockAt field other.x other.y other.z

structure LatticePosition where
  x : Int
  y : Int
  z : Int

axiom latticePosition : Terrain.Position → LatticePosition

axiom latticePositionSemantics (position : Terrain.Position) :
  latticePosition position = {
    x := Int.ofNat position.x
    y := Int.ofNat position.y
    z := Int.ofNat position.z }

axiom naturalPosition : LatticePosition → Terrain.Position

axiom naturalPositionSemantics (position : LatticePosition) :
  naturalPosition position = {
    x := position.x.toNat
    y := position.y.toNat
    z := position.z.toNat }

opaque latticeInside : Terrain.Dimensions → LatticePosition → Prop

axiom latticeInsideSemantics
    (dimensions : Terrain.Dimensions) (position : LatticePosition) :
  latticeInside dimensions position ↔
    0 ≤ position.x ∧ position.x.toNat < dimensions.width ∧
    0 ≤ position.y ∧ position.y.toNat < dimensions.verticalSize ∧
    0 ≤ position.z ∧ position.z.toNat < dimensions.depth

opaque axisNeighborOrder : LatticePosition → List LatticePosition

axiom axisNeighborOrderSemantics (position : LatticePosition) :
  axisNeighborOrder position = [
    { x := position.x - 1, y := position.y, z := position.z },
    { x := position.x + 1, y := position.y, z := position.z },
    { x := position.x, y := position.y - 1, z := position.z },
    { x := position.x, y := position.y + 1, z := position.z },
    { x := position.x, y := position.y, z := position.z - 1 },
    { x := position.x, y := position.y, z := position.z + 1 }]

opaque fallingMaterial : Nat → Prop

axiom fallingMaterialSemantics (material : Nat) :
  fallingMaterial material ↔
    material = Terrain.sandId ∨ material = Terrain.gravelId

opaque fallPassable : Nat → Prop

axiom fallPassableSemantics (material : Nat) :
  fallPassable material ↔
    material = Terrain.airId ∨
    material = Terrain.flowingWaterId ∨
    material = Terrain.stillWaterId ∨
    material = Terrain.flowingLavaId ∨
    material = Terrain.stillLavaId

opaque fallingDestination :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Nat

axiom fallingDestinationSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (source : Terrain.Position) (inside : Terrain.inside dimensions source) :
  let destinationY := fallingDestination dimensions field source
  destinationY ≤ source.y ∧
    (∀ y : Nat, destinationY ≤ y → y < source.y →
      fallPassable (Terrain.blockAt field source.x y source.z)) ∧
    (destinationY = 0 ∨
      ¬ fallPassable
        (Terrain.blockAt field source.x (destinationY - 1) source.z))

axiom movedFallingField :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Terrain.BlockField

axiom movedFallingFieldSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (source : Terrain.Position) :
  let destination : Terrain.Position := {
    x := source.x
    y := fallingDestination dimensions field source
    z := source.z }
  movedFallingField dimensions field source =
    if destination.y = source.y then field
    else overwriteBlock
      (overwriteBlock field source Terrain.airId)
      destination
      (Terrain.blockAt field source.x source.y source.z)

axiom deliverFallingNotifications :
  Terrain.Dimensions → Terrain.BlockField → List LatticePosition → Terrain.BlockField

axiom fallingNeighborReaction :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Terrain.BlockField

axiom deliverFallingNotificationsEmpty
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField) :
  deliverFallingNotifications dimensions field [] = field

axiom deliverFallingNotificationsOutside
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : LatticePosition) (remaining : List LatticePosition)
    (outside : ¬ latticeInside dimensions position) :
  deliverFallingNotifications dimensions field (position :: remaining) =
    deliverFallingNotifications dimensions field remaining

axiom deliverFallingNotificationsPassive
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : LatticePosition) (remaining : List LatticePosition)
    (inside : latticeInside dimensions position)
    (passive : ¬ fallingMaterial
      (Terrain.blockAt field position.x.toNat position.y.toNat position.z.toNat)) :
  deliverFallingNotifications dimensions field (position :: remaining) =
    deliverFallingNotifications dimensions field remaining

axiom deliverFallingNotificationsReactive
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : LatticePosition) (remaining : List LatticePosition)
    (inside : latticeInside dimensions position)
    (reactive : fallingMaterial
      (Terrain.blockAt field position.x.toNat position.y.toNat position.z.toNat)) :
  deliverFallingNotifications dimensions field (position :: remaining) =
    deliverFallingNotifications dimensions
      (fallingNeighborReaction dimensions field (naturalPosition position)) remaining

axiom fallingNeighborReactionStationary
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (source : Terrain.Position) (inside : Terrain.inside dimensions source)
    (stationary : fallingDestination dimensions field source = source.y) :
  fallingNeighborReaction dimensions field source = field

axiom fallingNeighborReactionMoved
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (source : Terrain.Position) (inside : Terrain.inside dimensions source)
    (moved : fallingDestination dimensions field source ≠ source.y) :
  let destination : Terrain.Position := {
    x := source.x
    y := fallingDestination dimensions field source
    z := source.z }
  fallingNeighborReaction dimensions field source =
    deliverFallingNotifications dimensions
      (movedFallingField dimensions field source)
      (axisNeighborOrder (latticePosition source) ++
        axisNeighborOrder (latticePosition destination))

axiom notifyingBlockPlacement :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Nat → Terrain.BlockField

axiom notifyingBlockPlacementUnchanged
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : Terrain.Position) (material : Nat)
    (same : Terrain.blockAt field position.x position.y position.z = material) :
  notifyingBlockPlacement dimensions field position material = field

axiom notifyingBlockPlacementChanged
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : Terrain.Position) (material : Nat)
    (inside : Terrain.inside dimensions position)
    (changed : Terrain.blockAt field position.x position.y position.z ≠ material) :
  notifyingBlockPlacement dimensions field position material =
    deliverFallingNotifications dimensions
      (overwriteBlock field position material)
      (axisNeighborOrder (latticePosition position))

theorem placementIntoAirNotifiesAxisNeighbors
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : Terrain.Position) (material : Nat)
    (inside : Terrain.inside dimensions position)
    (air : Terrain.blockAt field position.x position.y position.z = Terrain.airId)
    (nonair : material ≠ Terrain.airId) :
  notifyingBlockPlacement dimensions field position material =
    deliverFallingNotifications dimensions
      (overwriteBlock field position material)
      (axisNeighborOrder (latticePosition position)) := by
  apply notifyingBlockPlacementChanged dimensions field position material inside
  intro same
  apply nonair
  calc
    material = Terrain.blockAt field position.x position.y position.z := same.symm
    _ = Terrain.airId := air

axiom prepareTreeBase :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Terrain.BlockField

axiom prepareTreeBaseSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (base : Terrain.Position) (positive : 0 < base.y) :
  prepareTreeBase dimensions field base = notifyingBlockPlacement dimensions field
    { x := base.x, y := base.y - 1, z := base.z } Terrain.dirtId

opaque canopyLayer : Terrain.Position → Nat → Terrain.Position → Nat

axiom canopyLayerSemantics
    (base : Terrain.Position) (height : Nat) (position : Terrain.Position)
    (vertical : base.y + height - 3 ≤ position.y ∧ position.y ≤ base.y + height) :
  position.y + 3 = base.y + height + canopyLayer base height position

opaque canopyRadius : Terrain.Position → Nat → Terrain.Position → Nat

axiom canopyRadiusSemantics
    (base : Terrain.Position) (height : Nat) (position : Terrain.Position) :
  canopyRadius base height position =
    if canopyLayer base height position < 2 then 2 else 1

opaque canopyCell : Terrain.Position → Nat → Terrain.Position → Prop

axiom canopyCellSemantics
    (base : Terrain.Position) (height : Nat) (position : Terrain.Position) :
  canopyCell base height position ↔
    canopyLayer base height position < 4 ∧
    position.y + 3 = base.y + height + canopyLayer base height position ∧
    horizontalDistance base.x position.x ≤ canopyRadius base height position ∧
    horizontalDistance base.z position.z ≤ canopyRadius base height position

opaque canopyCorner : Terrain.Position → Nat → Terrain.Position → Prop

axiom canopyCornerSemantics
    (base : Terrain.Position) (height : Nat) (position : Terrain.Position) :
  canopyCorner base height position ↔
    canopyCell base height position ∧
    horizontalDistance base.x position.x = canopyRadius base height position ∧
    horizontalDistance base.z position.z = canopyRadius base height position

opaque canopyTraversal : Terrain.Position → Nat → List Terrain.Position

axiom canopyTraversalMembership
    (base : Terrain.Position) (height : Nat) (position : Terrain.Position) :
  position ∈ canopyTraversal base height ↔ canopyCell base height position

axiom canopyTraversalDistinct (base : Terrain.Position) (height : Nat) :
  (canopyTraversal base height).Nodup

axiom canopyTraversalOrder
    (base left right : Terrain.Position) (height : Nat)
    (before between after : List Terrain.Position)
    (listed : canopyTraversal base height =
      before ++ left :: between ++ right :: after) :
  left.y < right.y ∨
    (left.y = right.y ∧ left.x < right.x) ∨
    (left.y = right.y ∧ left.x = right.x ∧ left.z < right.z)

inductive BoundedDrawSequence :
    Nat → Nat → Random.State → Random.State → Prop where
  | done (bound : Nat) (state : Random.State) :
      BoundedDrawSequence 0 bound state state
  | step
      (remaining bound value : Nat)
      (state drawnState finalState : Random.State)
      (draw : Random.nextIntBounded state bound = (value, drawnState))
      (rest : BoundedDrawSequence remaining bound drawnState finalState) :
      BoundedDrawSequence (remaining + 1) bound state finalState

inductive CanopyPlacement :
    Terrain.Dimensions → Terrain.Position → Nat → List Terrain.Position → Random.State →
      Terrain.BlockField → Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions)
      (base : Terrain.Position) (height : Nat)
      (state : Random.State) (field : Terrain.BlockField) :
      CanopyPlacement dimensions base height [] state field state field
  | filled
      (dimensions : Terrain.Dimensions)
      (base : Terrain.Position) (height : Nat) (position : Terrain.Position)
      (remaining : List Terrain.Position)
      (state finalState : Random.State) (field finalField : Terrain.BlockField)
      (notCorner : ¬ canopyCorner base height position)
      (rest : CanopyPlacement dimensions base height remaining state
        (notifyingBlockPlacement dimensions field position foliageId)
        finalState finalField) :
      CanopyPlacement dimensions base height (position :: remaining) state field
        finalState finalField

  | keptCorner
      (dimensions : Terrain.Dimensions)
      (base : Terrain.Position) (height : Nat) (position : Terrain.Position)
      (remaining : List Terrain.Position)
      (state drawnState finalState : Random.State)
      (field finalField : Terrain.BlockField) (choice : Nat)
      (corner : canopyCorner base height position)
      (draw : Random.nextIntBounded state 2 = (choice, drawnState))
      (kept : choice ≠ 0 ∧ canopyLayer base height position ≠ 3)
      (rest : CanopyPlacement dimensions base height remaining drawnState
        (notifyingBlockPlacement dimensions field position foliageId)
        finalState finalField) :
      CanopyPlacement dimensions base height (position :: remaining) state field
        finalState finalField

  | skippedCorner
      (dimensions : Terrain.Dimensions)
      (base : Terrain.Position) (height : Nat) (position : Terrain.Position)
      (remaining : List Terrain.Position)
      (state drawnState finalState : Random.State)
      (field finalField : Terrain.BlockField) (choice : Nat)
      (corner : canopyCorner base height position)
      (draw : Random.nextIntBounded state 2 = (choice, drawnState))
      (skipped : choice = 0 ∨ canopyLayer base height position = 3)
      (rest : CanopyPlacement dimensions base height remaining drawnState field
        finalState finalField) :
      CanopyPlacement dimensions base height (position :: remaining) state field
        finalState finalField

axiom canopyPlacementConsumesSixteenCornerDraws
    (dimensions : Terrain.Dimensions)
    (base : Terrain.Position) (height : Nat)
    (initialState finalState : Random.State)
    (initialField finalField : Terrain.BlockField)
    (placement : CanopyPlacement dimensions base height (canopyTraversal base height)
      initialState initialField finalState finalField) :
  BoundedDrawSequence 16 2 initialState finalState

axiom notifyingPlacementSequence :
  Terrain.Dimensions → Terrain.BlockField → List Terrain.Position → Nat → Terrain.BlockField

axiom notifyingPlacementSequenceEmpty
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField) (material : Nat) :
  notifyingPlacementSequence dimensions field [] material = field

axiom notifyingPlacementSequenceStep
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (position : Terrain.Position) (remaining : List Terrain.Position) (material : Nat) :
  notifyingPlacementSequence dimensions field (position :: remaining) material =
    notifyingPlacementSequence dimensions
      (notifyingBlockPlacement dimensions field position material) remaining material

opaque trunkTraversal : Terrain.Position → Nat → List Terrain.Position

axiom trunkTraversalMembership
    (base position : Terrain.Position) (height : Nat) :
  position ∈ trunkTraversal base height ↔
    position.x = base.x ∧ position.z = base.z ∧
    base.y ≤ position.y ∧ position.y < base.y + height

axiom trunkTraversalDistinct (base : Terrain.Position) (height : Nat) :
  (trunkTraversal base height).Nodup

axiom trunkTraversalOrder
    (base left right : Terrain.Position) (height : Nat)
    (before between after : List Terrain.Position)
    (listed : trunkTraversal base height =
      before ++ left :: between ++ right :: after) :
  left.y < right.y

axiom placeTrunk :
  Terrain.Dimensions → Terrain.BlockField → Terrain.Position → Nat → Terrain.BlockField

axiom placeTrunkSemantics
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (base : Terrain.Position) (height : Nat) :
  placeTrunk dimensions field base height =
    notifyingPlacementSequence dimensions field (trunkTraversal base height) trunkId

axiom placeTrunkInside
    (dimensions : Terrain.Dimensions) (field : Terrain.BlockField)
    (base position : Terrain.Position) (height : Nat)
    (sameColumn : position.x = base.x ∧ position.z = base.z)
    (vertical : base.y ≤ position.y ∧ position.y < base.y + height) :
  Terrain.blockAt (placeTrunk dimensions field base height)
    position.x position.y position.z = trunkId

structure TreeGrowthResult where
  state : Random.State
  field : Terrain.BlockField
  succeeded : Bool

axiom growTree :
  Terrain.Dimensions → Random.State → Terrain.BlockField →
    Terrain.Position → TreeGrowthResult

axiom growTreeFailure
    (dimensions : Terrain.Dimensions) (state : Random.State)
    (field : Terrain.BlockField) (base : Terrain.Position)
    (ineligible : ¬ treeEligible dimensions field base
      ((Random.nextIntBounded state 3).1 + 4)) :
  growTree dimensions state field base = {
    state := (Random.nextIntBounded state 3).2
    field := field
    succeeded := false }

axiom growTreeSuccess
    (dimensions : Terrain.Dimensions) (state finalState : Random.State)
    (field canopyField : Terrain.BlockField) (base : Terrain.Position)
    (eligible : treeEligible dimensions field base
      ((Random.nextIntBounded state 3).1 + 4))
    (canopy : CanopyPlacement dimensions base ((Random.nextIntBounded state 3).1 + 4)
      (canopyTraversal base ((Random.nextIntBounded state 3).1 + 4))
      (Random.nextIntBounded state 3).2 (prepareTreeBase dimensions field base)
      finalState canopyField) :
  growTree dimensions state field base = {
    state := finalState
    field := placeTrunk dimensions canopyField base
      ((Random.nextIntBounded state 3).1 + 4)
    succeeded := true }

axiom eligibleTreeHasCanopyPlacement
    (dimensions : Terrain.Dimensions) (state : Random.State)
    (field : Terrain.BlockField) (base : Terrain.Position)
    (eligible : treeEligible dimensions field base
      ((Random.nextIntBounded state 3).1 + 4)) :
  ∃ canopyField : Terrain.BlockField,
    CanopyPlacement dimensions base ((Random.nextIntBounded state 3).1 + 4)
      (canopyTraversal base ((Random.nextIntBounded state 3).1 + 4))
      (Random.nextIntBounded state 3).2 (prepareTreeBase dimensions field base)
      (growTree dimensions state field base).state canopyField ∧
    (growTree dimensions state field base).field =
      placeTrunk dimensions canopyField base
        ((Random.nextIntBounded state 3).1 + 4) ∧
    (growTree dimensions state field base).succeeded = true

axiom successfulTreeHeightRange
    (dimensions : Terrain.Dimensions) (state : Random.State)
    (field : Terrain.BlockField) (base : Terrain.Position)
    (success : (growTree dimensions state field base).succeeded = true) :
  4 ≤ (Random.nextIntBounded state 3).1 + 4 ∧
    (Random.nextIntBounded state 3).1 + 4 ≤ 6

structure TreeCandidateResult where
  generatorState : Random.State
  levelState : Random.State
  field : Terrain.BlockField
  point : HorizontalWalkPoint

opaque horizontalInside : Terrain.Dimensions → HorizontalWalkPoint → Prop

axiom horizontalInsideSemantics
    (dimensions : Terrain.Dimensions) (point : HorizontalWalkPoint) :
  horizontalInside dimensions point ↔
    0 ≤ point.x ∧ point.x.toNat < dimensions.width ∧
    0 ≤ point.z ∧ point.z.toNat < dimensions.depth

axiom treeCandidateStep :
  Terrain.Dimensions → Terrain.ElevationNoise → Random.State → Random.State →
    Terrain.BlockField → HorizontalWalkPoint → TreeCandidateResult

axiom treeCandidateStepPoint
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (generatorState levelState : Random.State) (field : Terrain.BlockField)
    (point : HorizontalWalkPoint) :
  let xPositive := Random.nextIntBounded generatorState 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let zPositive := Random.nextIntBounded xNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  (treeCandidateStep dimensions elevation generatorState levelState field point).point = {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }

axiom treeCandidateStepOutside
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (generatorState levelState : Random.State) (field : Terrain.BlockField)
    (point : HorizontalWalkPoint) :
  let xPositive := Random.nextIntBounded generatorState 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let zPositive := Random.nextIntBounded xNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  let nextPoint : HorizontalWalkPoint := {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }
  ¬ horizontalInside dimensions nextPoint →
    (treeCandidateStep dimensions elevation generatorState levelState field point).generatorState =
      zNegative.2 ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).levelState =
      levelState ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).field =
      field

axiom treeCandidateStepSkipped
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (generatorState levelState : Random.State) (field : Terrain.BlockField)
    (point : HorizontalWalkPoint) :
  let xPositive := Random.nextIntBounded generatorState 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let zPositive := Random.nextIntBounded xNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  let nextPoint : HorizontalWalkPoint := {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }
  let decision := Random.nextIntBounded zNegative.2 4
  horizontalInside dimensions nextPoint → decision.1 ≠ 0 →
    (treeCandidateStep dimensions elevation generatorState levelState field point).generatorState =
      decision.2 ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).levelState =
      levelState ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).field =
      field

axiom treeCandidateStepGrowth
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (generatorState levelState : Random.State) (field : Terrain.BlockField)
    (point : HorizontalWalkPoint) :
  let xPositive := Random.nextIntBounded generatorState 6
  let xNegative := Random.nextIntBounded xPositive.2 6
  let zPositive := Random.nextIntBounded xNegative.2 6
  let zNegative := Random.nextIntBounded zPositive.2 6
  let nextPoint : HorizontalWalkPoint := {
    x := point.x + Int.ofNat xPositive.1 - Int.ofNat xNegative.1
    z := point.z + Int.ofNat zPositive.1 - Int.ofNat zNegative.1 }
  let decision := Random.nextIntBounded zNegative.2 4
  let base : Terrain.Position := {
    x := nextPoint.x.toNat
    y := Terrain.surfaceHeight dimensions elevation nextPoint.x.toNat nextPoint.z.toNat + 1
    z := nextPoint.z.toNat }
  let growth := growTree dimensions levelState field base
  horizontalInside dimensions nextPoint → decision.1 = 0 →
    (treeCandidateStep dimensions elevation generatorState levelState field point).generatorState =
      decision.2 ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).levelState =
      growth.state ∧
    (treeCandidateStep dimensions elevation generatorState levelState field point).field =
      growth.field

inductive TreeWalk :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → Random.State → Random.State →
      Terrain.BlockField → HorizontalWalkPoint → Random.State → Random.State →
      Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (generatorState levelState : Random.State) (field : Terrain.BlockField)
      (point : HorizontalWalkPoint) :
      TreeWalk 0 dimensions elevation generatorState levelState field point
        generatorState levelState field
  | step
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise)
      (generatorState levelState finalGeneratorState finalLevelState : Random.State)
      (field finalField : Terrain.BlockField) (point : HorizontalWalkPoint)
      (rest : TreeWalk remaining dimensions elevation
        (treeCandidateStep dimensions elevation generatorState levelState field point).generatorState
        (treeCandidateStep dimensions elevation generatorState levelState field point).levelState
        (treeCandidateStep dimensions elevation generatorState levelState field point).field
        (treeCandidateStep dimensions elevation generatorState levelState field point).point
        finalGeneratorState finalLevelState finalField) :
      TreeWalk (remaining + 1) dimensions elevation generatorState levelState field point
        finalGeneratorState finalLevelState finalField

inductive TreeCluster :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → HorizontalWalkPoint →
      Random.State → Random.State → Terrain.BlockField → Random.State → Random.State →
      Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (origin : HorizontalWalkPoint) (generatorState levelState : Random.State)
      (field : Terrain.BlockField) :
      TreeCluster 0 dimensions elevation origin generatorState levelState field
        generatorState levelState field
  | walk
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise) (origin : HorizontalWalkPoint)
      (generatorState levelState walkGeneratorState walkLevelState
        finalGeneratorState finalLevelState : Random.State)
      (field walkField finalField : Terrain.BlockField)
      (oneWalk : TreeWalk 20 dimensions elevation generatorState levelState field origin
        walkGeneratorState walkLevelState walkField)
      (rest : TreeCluster remaining dimensions elevation origin
        walkGeneratorState walkLevelState walkField
        finalGeneratorState finalLevelState finalField) :
      TreeCluster (remaining + 1) dimensions elevation origin
        generatorState levelState field finalGeneratorState finalLevelState finalField

opaque treeClusterCount : Terrain.Dimensions → Nat

axiom treeClusterCountSemantics (dimensions : Terrain.Dimensions) :
  treeClusterCount dimensions = dimensions.width * dimensions.depth / 4000

inductive TreePlacement :
    Nat → Terrain.Dimensions → Terrain.ElevationNoise → Random.State → Random.State →
      Terrain.BlockField → Random.State → Random.State → Terrain.BlockField → Prop where
  | done
      (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
      (generatorState levelState : Random.State) (field : Terrain.BlockField) :
      TreePlacement 0 dimensions elevation generatorState levelState field
        generatorState levelState field
  | cluster
      (remaining : Nat) (dimensions : Terrain.Dimensions)
      (elevation : Terrain.ElevationNoise)
      (generatorState levelState xState zState clusterGeneratorState
        clusterLevelState finalGeneratorState finalLevelState : Random.State)
      (field clusterField finalField : Terrain.BlockField) (x z : Nat)
      (xDraw : Random.nextIntBounded generatorState dimensions.width = (x, xState))
      (zDraw : Random.nextIntBounded xState dimensions.depth = (z, zState))
      (oneCluster : TreeCluster 20 dimensions elevation
        { x := Int.ofNat x, z := Int.ofNat z }
        zState levelState field clusterGeneratorState clusterLevelState clusterField)
      (rest : TreePlacement remaining dimensions elevation
        clusterGeneratorState clusterLevelState clusterField
        finalGeneratorState finalLevelState finalField) :
      TreePlacement (remaining + 1) dimensions elevation generatorState levelState field
        finalGeneratorState finalLevelState finalField

structure TreePassResult where
  generatorState : Random.State
  levelState : Random.State
  field : Terrain.BlockField

axiom treePass :
  Terrain.Dimensions → Terrain.ElevationNoise → Random.State → Random.State →
    Terrain.BlockField → TreePassResult

axiom treePassSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (generatorState levelState : Random.State) (field : Terrain.BlockField) :
  TreePlacement (treeClusterCount dimensions) dimensions elevation
    generatorState levelState field
    (treePass dimensions elevation generatorState levelState field).generatorState
    (treePass dimensions elevation generatorState levelState field).levelState
    (treePass dimensions elevation generatorState levelState field).field

structure GrassSpreadingResult where
  noise : Terrain.SurfaceNoise
  state : Random.State
  field : Terrain.BlockField

axiom grassSpreadingPass :
  Terrain.Dimensions → Terrain.ElevationNoise → Random.State →
    Terrain.BlockField → GrassSpreadingResult

axiom grassSpreadingPassSemantics
    (dimensions : Terrain.Dimensions) (elevation : Terrain.ElevationNoise)
    (state : Random.State) (field : Terrain.BlockField) :
  let surfaceNoise := Terrain.surfaceNoiseFromRandom state
  grassSpreadingPass dimensions elevation state field = {
    noise := surfaceNoise.1
    state := surfaceNoise.2
    field := Terrain.surfacedTerrain dimensions elevation surfaceNoise.1 field }

structure GenerationResult where
  generatorState : Random.State
  levelState : Random.State
  field : Terrain.BlockField

axiom generatedLevel : Terrain.Dimensions → Int → GenerationResult

axiom generatedLevelSemantics (dimensions : Terrain.Dimensions) (seed : Int) :
  let generatorInitial := Random.initialState seed
  let elevation := Terrain.elevationNoiseFromRandom generatorInitial
  let soil := Terrain.soiledTerrain dimensions elevation.1
  let carvedAndOres := Ore.carvingAndResources dimensions elevation.2 soil
  let boundaryWater := Terrain.boundaryWaterPass dimensions carvedAndOres.2
  let inlandWater := Terrain.inlandWaterPass dimensions carvedAndOres.1 boundaryWater
  let lava := Terrain.lavaPass dimensions inlandWater.1 inlandWater.2
  let grownSurface := grassSpreadingPass dimensions elevation.1 lava.1 lava.2
  let flowers := flowerPass dimensions elevation.1 grownSurface.state grownSurface.field
  let mushrooms := mushroomPass dimensions elevation.1 flowers.1 flowers.2
  let levelConstructorDraw := Random.nextInt (Random.initialState seed)
  let trees := treePass dimensions elevation.1 mushrooms.1 levelConstructorDraw.2 mushrooms.2
  generatedLevel dimensions seed = {
    generatorState := trees.generatorState
    levelState := trees.levelState
    field := trees.field }

axiom finalMaterialExhaustive
    (dimensions : Terrain.Dimensions) (seed : Int) (position : Terrain.Position)
    (inside : Terrain.inside dimensions position) :
  let material := Terrain.blockAt (generatedLevel dimensions seed).field
    position.x position.y position.z
  material = Terrain.airId ∨
  material = Terrain.stoneId ∨
  material = Terrain.grassId ∨
  material = Terrain.dirtId ∨
  material = Terrain.stillWaterId ∨
  material = Terrain.flowingLavaId ∨
  material = Terrain.stillLavaId ∨
  material = Terrain.sandId ∨
  material = Terrain.gravelId ∨
  material = Ore.resourceMaterial Ore.ResourceKind.gold ∨
  material = Ore.resourceMaterial Ore.ResourceKind.iron ∨
  material = Ore.resourceMaterial Ore.ResourceKind.coal ∨
  material = trunkId ∨
  material = foliageId ∨
  material = firstFlowerId ∨
  material = secondFlowerId ∨
  material = firstMushroomId ∨
  material = secondMushroomId

theorem flowerAttemptsScaleWithArea (dimensions : Terrain.Dimensions) :
    flowerAttemptCount dimensions = dimensions.width * dimensions.depth / 3000 :=
  flowerAttemptCountSemantics dimensions

theorem mushroomAttemptsScaleWithVolume (dimensions : Terrain.Dimensions) :
    mushroomAttemptCount dimensions =
      dimensions.width * dimensions.depth * dimensions.verticalSize / 2000 :=
  mushroomAttemptCountSemantics dimensions

theorem treeClustersScaleWithArea (dimensions : Terrain.Dimensions) :
    treeClusterCount dimensions = dimensions.width * dimensions.depth / 4000 :=
  treeClusterCountSemantics dimensions

theorem treeHeightsAreFourThroughSix
    (dimensions : Terrain.Dimensions) (state : Random.State)
    (field : Terrain.BlockField) (base : Terrain.Position)
    (success : (growTree dimensions state field base).succeeded = true) :
    4 ≤ (Random.nextIntBounded state 3).1 + 4 ∧
      (Random.nextIntBounded state 3).1 + 4 ≤ 6 :=
  successfulTreeHeightRange dimensions state field base success

theorem seedStartsIndependentGeneratorAndLevelStreams
    (_dimensions : Terrain.Dimensions) (seed : Int) :
  let generatorInitial := Random.initialState seed
  let levelInitial := Random.initialState seed
  generatorInitial = levelInitial := by
  rfl

end Spec.Level
