import * as THREE from "three"
import { Walkmesh } from "game/walkmesh"

// Builds the static room ("env") scene, the character ("actor") scene and the
// fixed camera from the room definition JSON delivered by the server.
export function buildWorld(room) {
  const walkmesh = new Walkmesh(room.walkmesh)

  const envScene = new THREE.Scene()
  const actorScene = new THREE.Scene()

  addLights(envScene, room)
  addLights(actorScene, room)

  // A room can supply a photographic `backdrop` (a real pre-rendered image)
  // instead of primitive scenery. In that mode the image is all we draw for
  // color; every prop becomes an invisible, depth-only occluder so live
  // characters are still correctly hidden behind foreground scenery (the
  // fountain, the front chairs) exactly like the primitive-rendered rooms.
  let backdropTexture = null
  let ready = Promise.resolve()
  if (room.backdrop) {
    ready = new Promise(resolve => {
      backdropTexture = new THREE.TextureLoader().load(room.backdrop, resolve, undefined, resolve)
    })
    for (const prop of room.props || []) envScene.add(propMesh(prop, true))
  } else {
    envScene.background = new THREE.Color(room.background || "#0a0a14")
    envScene.add(groundMesh(room))
    for (const prop of room.props || []) envScene.add(propMesh(prop))
  }

  const cam = room.camera
  const camera = new THREE.PerspectiveCamera(cam.fov || 40, 1, 0.1, 200)
  camera.position.set(...cam.position)
  camera.lookAt(new THREE.Vector3(...cam.look_at))

  return { room, walkmesh, envScene, actorScene, camera, backdropTexture, ready }
}

// The FF7/RE trick: render the static room ONCE into a color+depth target.
// Every frame afterwards we draw that image as a fullscreen quad that also
// writes the stored per-pixel depth, so live characters rendered on top are
// correctly occluded by foreground scenery.
export function prerenderBackground(renderer, world, width, height) {
  const depthTexture = new THREE.DepthTexture(width, height)
  const target = new THREE.WebGLRenderTarget(width, height, {
    depthTexture,
    samples: 0,
    minFilter: THREE.NearestFilter,
    magFilter: THREE.NearestFilter
  })

  renderer.setRenderTarget(target)
  renderer.clear()
  renderer.render(world.envScene, world.camera)
  renderer.setRenderTarget(null)

  // Photo-backdrop rooms sample the image directly for color (the render
  // target only carries occluder depth). Cover-fit the image to the viewport
  // so its own aspect is preserved instead of stretched to the frame.
  const photo = world.backdropTexture
  const cover = new THREE.Vector2(1, 1)
  if (photo && photo.image) {
    const imageAspect = photo.image.width / photo.image.height
    const viewAspect = width / height
    if (viewAspect > imageAspect) cover.set(1, imageAspect / viewAspect)
    else cover.set(viewAspect / imageAspect, 1)
  }

  const material = new THREE.RawShaderMaterial({
    glslVersion: THREE.GLSL3,
    uniforms: {
      tColor: { value: target.texture },
      tDepth: { value: depthTexture },
      tPhoto: { value: photo },
      uUsePhoto: { value: photo ? 1 : 0 },
      uCover: { value: cover }
    },
    vertexShader: `
      in vec3 position;
      in vec2 uv;
      out vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = vec4(position.xy, 0.0, 1.0);
      }
    `,
    fragmentShader: `
      precision highp float;
      uniform sampler2D tColor;
      uniform sampler2D tDepth;
      uniform sampler2D tPhoto;
      uniform int uUsePhoto;
      uniform vec2 uCover;
      in vec2 vUv;
      out vec4 outColor;
      void main() {
        vec3 rgb;
        if (uUsePhoto == 1) {
          // The photo is already sRGB-encoded; sampled raw and drawn straight
          // to the canvas it displays at the right brightness with no gamma
          // step (unlike the linear render-target path below).
          vec2 uv = vec2(0.5) + (vUv - vec2(0.5)) * uCover;
          rgb = texture(tPhoto, uv).rgb;
        } else {
          // The render target holds linear values; rendering the quad straight
          // to the canvas skips three's output color-space conversion, so
          // gamma-encode here to match the sRGB character pass.
          rgb = pow(texture(tColor, vUv).rgb, vec3(1.0 / 2.2));
        }
        outColor = vec4(rgb, 1.0);
        gl_FragDepth = texture(tDepth, vUv).r;
      }
    `,
    depthTest: true,
    depthWrite: true,
    depthFunc: THREE.AlwaysDepth
  })

  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material)
  quad.frustumCulled = false

  const scene = new THREE.Scene()
  scene.add(quad)
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1)

  return {
    scene,
    camera,
    dispose() {
      target.dispose()
      depthTexture.dispose()
      quad.geometry.dispose()
      material.dispose()
    }
  }
}

function addLights(scene, room) {
  const lights = room.lights || {}
  const ambient = lights.ambient || {}
  scene.add(new THREE.AmbientLight(ambient.color || "#8888aa", ambient.intensity ?? 1.2))

  const sun = lights.directional || {}
  const dir = new THREE.DirectionalLight(sun.color || "#ffeedd", sun.intensity ?? 1.6)
  dir.position.set(...(sun.position || [6, 12, 4]))
  scene.add(dir)
}

// Ground rendered from the walkmesh itself, non-indexed with a little
// per-triangle shade jitter — reads as cheap dithered floor texture.
function groundMesh(room) {
  const { vertices, triangles } = room.walkmesh
  const base = new THREE.Color(room.ground_color || "#665544")

  const positions = new Float32Array(triangles.length * 9)
  const colors = new Float32Array(triangles.length * 9)
  const tri = new THREE.Color()

  triangles.forEach(([ia, ib, ic], t) => {
    const jitter = 1 + (pseudoRandom(t) - 0.5) * 0.16
    tri.copy(base).multiplyScalar(jitter)
    ;[ia, ib, ic].forEach((vi, k) => {
      const o = t * 9 + k * 3
      positions[o] = vertices[vi][0]
      positions[o + 1] = vertices[vi][1]
      positions[o + 2] = vertices[vi][2]
      colors[o] = tri.r
      colors[o + 1] = tri.g
      colors[o + 2] = tri.b
    })
  })

  const geometry = new THREE.BufferGeometry()
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3))
  geometry.computeVertexNormals()

  return new THREE.Mesh(geometry, new THREE.MeshLambertMaterial({ vertexColors: true }))
}

function propMesh(prop, occluder = false) {
  let geometry
  switch (prop.type) {
    case "box":
      geometry = new THREE.BoxGeometry(...prop.size)
      break
    case "cylinder":
      geometry = new THREE.CylinderGeometry(prop.r2 ?? prop.r, prop.r, prop.h, prop.segments || 10)
      break
    case "cone":
      geometry = new THREE.ConeGeometry(prop.r, prop.h, prop.segments || 8)
      break
    case "sphere":
      geometry = new THREE.SphereGeometry(prop.r, prop.segments || 8, 6)
      break
    case "plane":
      geometry = new THREE.PlaneGeometry(prop.size[0], prop.size[1])
      break
    default:
      geometry = new THREE.BoxGeometry(1, 1, 1)
  }

  const material = new THREE.MeshLambertMaterial({
    color: prop.color || "#888888",
    emissive: prop.emissive || "#000000"
  })
  // Occluders live only in the depth buffer: invisible, but they still hide
  // characters that walk behind them.
  if (occluder) material.colorWrite = false
  const mesh = new THREE.Mesh(geometry, material)
  mesh.position.set(...prop.pos)
  if (prop.type === "plane") mesh.rotation.x = -Math.PI / 2
  if (prop.rot) mesh.rotation.y = prop.rot
  return mesh
}

function pseudoRandom(n) {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453
  return x - Math.floor(x)
}
