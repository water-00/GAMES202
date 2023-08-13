class DirectionalLight {

    // focalPoint：光线聚焦点

    constructor(lightIntensity, lightColor, lightPos, focalPoint, lightUp, hasShadowMap, gl) {
        this.mesh = Mesh.cube(setTransform(0, 0, 0, 0.2, 0.2, 0.2)); // 不平移，做scale = 0.2的缩放，返回这样的cube
        this.mat = new EmissiveMaterial(lightIntensity, lightColor);
        this.lightPos = lightPos;
        this.focalPoint = focalPoint;
        this.lightUp = lightUp

        this.hasShadowMap = hasShadowMap;
        this.fbo = new FBO(gl); // Frame Buffer Object
        if (!this.fbo) {
            console.log("无法设置帧缓冲区对象");
            return;
        }
    }

    CalcLightMVP(translate, scale) {
        let lightMVP = mat4.create();
        let modelMatrix = mat4.create();
        let viewMatrix = mat4.create();
        let projectionMatrix = mat4.create();
        
        // HOMEWORK
        
        // Model transform
        // 对顶点做平移、旋转、缩放变换
        mat4.translate(modelMatrix, modelMatrix, translate)
        mat4.scale(modelMatrix, modelMatrix, scale);

        // View transform
        // 把相机放到(0, 0, 0)，上方向为+Y，看向-Z，但是在glMatrix中调用lookAt函数即可
        mat4.lookAt(viewMatrix, this.lightPos, this.focalPoint, this.lightUp);

        // Projection transform
        // 用正交投影，正交投影的参数决定了shadow map所覆盖的范围
        const bound = 120;
        // out, left, right, bottom, top, near, far（后两个参数是frustum的近平面和远平面到camera的距离，而不是它们在空间中的坐标，坐标应该是一个负值）
        // WebGL是右手系，摄像机在(0, 0, 0)看向-Z
        mat4.ortho(projectionMatrix, -bound, bound, -bound, bound, 0.01, 400);
    

        mat4.multiply(lightMVP, projectionMatrix, viewMatrix);
        mat4.multiply(lightMVP, lightMVP, modelMatrix);

        return lightMVP;
    }
}
