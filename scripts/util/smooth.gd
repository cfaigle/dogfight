extends Node
static func exp_smooth(current: float, target: float, sharpness: float, dt: float) -> float:
    # sharpness ~ (1/seconds). Larger => snappier.
    var a = 1.0 - exp(-sharpness * dt)
    return lerp(current, target, a)

static func exp_smooth_v3(current: Vector3, target: Vector3, sharpness: float, dt: float) -> Vector3:
    var a = 1.0 - exp(-sharpness * dt)
    return current.lerp(target, a)

static func exp_smooth_q(current: Quaternion, target: Quaternion, sharpness: float, dt: float) -> Quaternion:
    var a = 1.0 - exp(-sharpness * dt)
    return current.slerp(target, a)
