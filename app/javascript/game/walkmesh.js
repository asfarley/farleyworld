// Triangle ground mesh the characters walk on. Positions live on the x/z
// plane; y (height) is interpolated barycentrically from the triangle under
// the point, so ramps and platforms "just work".
export class Walkmesh {
  constructor(data) {
    this.vertices = data.vertices
    this.triangles = data.triangles
  }

  heightAt(x, z) {
    for (const [ia, ib, ic] of this.triangles) {
      const a = this.vertices[ia], b = this.vertices[ib], c = this.vertices[ic]
      const w = barycentric(x, z, a, b, c)
      if (w) return a[1] * w[0] + b[1] * w[1] + c[1] * w[2]
    }
    return null
  }

  contains(x, z) {
    return this.heightAt(x, z) !== null
  }

  // Attempt a move from (fx,fz) to (tx,tz). If the target is off-mesh, try
  // sliding along each axis so walls feel smooth instead of sticky.
  resolveMove(fx, fz, tx, tz) {
    if (this.contains(tx, tz)) return [tx, tz]
    if (this.contains(tx, fz)) return [tx, fz]
    if (this.contains(fx, tz)) return [fx, tz]
    return [fx, fz]
  }
}

function barycentric(px, pz, a, b, c) {
  const v0x = c[0] - a[0], v0z = c[2] - a[2]
  const v1x = b[0] - a[0], v1z = b[2] - a[2]
  const v2x = px - a[0], v2z = pz - a[2]
  const dot00 = v0x * v0x + v0z * v0z
  const dot01 = v0x * v1x + v0z * v1z
  const dot02 = v0x * v2x + v0z * v2z
  const dot11 = v1x * v1x + v1z * v1z
  const dot12 = v1x * v2x + v1z * v2z
  const denom = dot00 * dot11 - dot01 * dot01
  if (Math.abs(denom) < 1e-9) return null
  const u = (dot11 * dot02 - dot01 * dot12) / denom
  const v = (dot00 * dot12 - dot01 * dot02) / denom
  if (u >= -1e-6 && v >= -1e-6 && u + v <= 1 + 1e-6) return [1 - u - v, v, u]
  return null
}
