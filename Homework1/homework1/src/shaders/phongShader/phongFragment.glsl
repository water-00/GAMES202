#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 100
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define LIGHT_WIDTH 110.0
#define CAMERA_WIDTH 240.0

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight; // 顶点以光源为视点下的坐标

highp float rand_1to1(highp float x) { 
  // -1 -1
  return fract(sin(x) * 10000.0);
}

highp float rand_2to1(vec2 uv) { 
  // 0 - 1
  const highp float a = 12.9898, b = 78.233, c = 43758.5453;
  highp float dt = dot(uv.xy, vec2(a, b)), sn = mod(dt, PI);
  return fract(sin(sn) * c);
}

float unpack(vec4 rgbaDepth) {
  const vec4 bitShift = vec4(1.0, 1.0 / 256.0, 1.0 / (256.0 * 256.0), 1.0 / (256.0 * 256.0 * 256.0));
  return dot(rgbaDepth, bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples(const in vec2 randomSeed) {

  float ANGLE_STEP = PI2 * float(NUM_RINGS) / float(NUM_SAMPLES); // 圆环数除以总的点数，再乘以2pi，就是下一个点需要增加的角度
  float INV_NUM_SAMPLES = 1.0 / float(NUM_SAMPLES);

  float angle = rand_2to1(randomSeed) * PI2; // 生成一个随机初始角度
  float radius = INV_NUM_SAMPLES; // disk初始半径
  float radiusStep = radius; // 每次递增半径

  for(int i = 0; i < NUM_SAMPLES; i++) {
    poissonDisk[i] = vec2(cos(angle), sin(angle)) * pow(radius, 0.75); // 分布中每个点的位置
    radius += radiusStep;
    angle += ANGLE_STEP;
  }
}

void uniformDiskSamples(const in vec2 randomSeed) {
  float randNum = rand_2to1(randomSeed);
  float sampleX = rand_1to1(randNum);
  float sampleY = rand_1to1(sampleX);

  float angle = sampleX * PI2;
  float radius = sqrt(sampleY);

  for(int i = 0; i < NUM_SAMPLES; i++) {
    poissonDisk[i] = vec2(radius * cos(angle), radius * sin(angle));

    sampleX = rand_1to1(sampleY);
    sampleY = rand_1to1(sampleX);

    angle = sampleX * PI2;
    radius = sqrt(sampleY);
  }
}

float calcBias() {
  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float c = 0.00;
  float bias = max(c * (1.0 - dot(normal, lightDir)), c); // 其实还没有搞懂这一行
  return bias;
}

// 遮挡物平均深度计算
float findBlocker(sampler2D shadowMap, vec2 uv, float zReceiver) {
  poissonDiskSamples(uv);
  float totalDepth = 0.0;
  float blocker = 0.0;
  float blockerSearch = zReceiver * LIGHT_WIDTH / CAMERA_WIDTH / 2.0; // 计算进行blockerSearch的范围
  for(int i = 0; i < BLOCKER_SEARCH_NUM_SAMPLES; i++) {
    vec2 uvOffset = poissonDisk[i] * blockerSearch; // 计算UV偏移
    float shadowDepth = unpack(texture2D(shadowMap, uv + uvOffset)); // 得到邻域shadowmap值
    if (shadowDepth + EPS + calcBias() < zReceiver) {
      totalDepth += shadowDepth;
      blocker++;
    }
  }
  // 特殊处理
  if(blocker - float(BLOCKER_SEARCH_NUM_SAMPLES) <= EPS)
    return 1.0;
  if(blocker <= EPS)
    return 0.0;
  // 返回平均深度
  return totalDepth / blocker;
}

float PCF(sampler2D shadowMap, vec4 coords) {
  // HOMEWORK
  poissonDiskSamples(coords.xy);

  float blocker = 0.0;
  float radius = 20.0;
    // 对分布中的每一个采样点计算是否被遮挡，算出被遮挡的点的比例
  for(int i = 0; i < NUM_SAMPLES; i++) {
    vec2 uv_bias = poissonDisk[i] * radius / 2048.0; // uv采样偏移 radius/2048.0为滤波器filterSize
    float shadowDepth = unpack(texture2D(shadowMap, coords.xy + uv_bias));
    if(coords.z > shadowDepth + EPS + calcBias()) {
      blocker++;
    }
  }
  return 1.0 - blocker / float(NUM_SAMPLES);
}

float PCF(sampler2D shadowMap, vec4 coords, float penumbra) {
  float blocker = 0.0;
  float radius = penumbra;

  for(int i = 0; i < NUM_SAMPLES; i++) {
    vec2 uv_bias = poissonDisk[i] * radius / 2048.0; // uv采样偏移 radius/2048.0为滤波器filterSize
    float shadowDepth = unpack(texture2D(shadowMap, coords.xy + uv_bias));
    if(coords.z > shadowDepth + EPS + calcBias()) {
      blocker++;
    }
  }
  return 1.0 - blocker / float(NUM_SAMPLES);
}

float PCSS(sampler2D shadowMap, vec4 coords) {
  // HOMEWORK

  // STEP 1: avgblocker depth
  float avgBlockerDepth = findBlocker(shadowMap, coords.xy, coords.z);
  // STEP 2: penumbra size
  float penumbra = (coords.z - avgBlockerDepth) * float(LIGHT_WIDTH) / avgBlockerDepth;
  // STEP 3: filtering
  return PCF(shadowMap, coords, penumbra);
}

float useShadowMap(sampler2D shadowMap, vec4 shadowCoord) {
  // HOMEWORK

  // Perform shadow depth query
  vec4 rgbaDepth = texture2D(shadowMap, shadowCoord.xy).rgba;
  float shadowDepth = unpack(rgbaDepth);

  // Compare current depth with shadow depth and return visibility
  if(shadowCoord.z > shadowDepth + calcBias()) {
    return 0.0;
  } else {
    return 1.0;
  }
}

vec3 blinnPhong() {
  vec3 color = texture2D(uSampler, vTextureCoord).rgb;
  color = pow(color, vec3(2.2));

  vec3 ambient = 0.05 * color;

  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float diff = max(dot(lightDir, normal), 0.0);
  vec3 light_atten_coff = uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
  vec3 diffuse = diff * light_atten_coff * color;

  vec3 viewDir = normalize(uCameraPos - vFragPos);
  vec3 halfDir = normalize((lightDir + viewDir));
  float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
  vec3 specular = uKs * light_atten_coff * spec;

  vec3 radiance = (ambient + diffuse + specular);
  vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
  return phongColor;
}

void main(void) {

  vec3 shadowCoord = ((vPositionFromLight.xyz / vPositionFromLight.w) + 1.0) / 2.0;
  float visibility;
  //visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  //visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0));
  visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));

  vec3 phongColor = blinnPhong();

  gl_FragColor = vec4(phongColor * visibility, 1.0);
  // gl_FragColor = vec4(phongColor, 1.0);
}