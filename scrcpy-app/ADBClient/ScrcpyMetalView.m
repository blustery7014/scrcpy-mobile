#import "ScrcpyMetalView.h"
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <SDL2/SDL_video.h>

typedef struct {
    vector_float2 position;
    vector_float2 texCoord;
} Vertex;

@interface ScrcpyMetalView () <MTKViewDelegate>

@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> rgbPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> yuvPipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLTexture> currentTexture;
@property (nonatomic, strong) id<MTLTexture> currentYTexture;
@property (nonatomic, strong) id<MTLTexture> currentUVTexture;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, assign) BOOL needsVertexUpdate;
@property (nonatomic, assign) BOOL isYUVFormat;

// 性能优化新增属性
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, strong) dispatch_semaphore_t frameSemaphore;
@property (nonatomic, assign) CFTimeInterval lastFrameTime;
@property (nonatomic, strong) NSMutableArray<id<MTLTexture>> *texturePool;
@property (nonatomic, assign) BOOL isRendering;
@property (nonatomic, strong) id<MTLLibrary> shaderLibrary;
@property (nonatomic, assign) CGSize lastDrawableSize;

@end

@implementation ScrcpyMetalView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if (self) {
        [self setupMetal];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.device = MTLCreateSystemDefaultDevice();
        [self setupMetal];
    }
    return self;
}

- (void)dealloc {
    // 移除通知监听
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    
    // 清理纹理池
    [self.texturePool removeAllObjects];
}

#pragma mark - Setup

- (void)setupMetal {
    if (!self.device) {
        NSLog(@"Metal is not supported on this device");
        return;
    }
    
    self.delegate = self;
    self.framebufferOnly = YES;
    self.autoResizeDrawable = YES;
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    self.enableSetNeedsDisplay = NO; // 改为NO，避免不必要的重绘
    self.paused = NO; // 改为NO，使用MTKView的自动刷新
    
    // 性能优化初始化
    self.maxFrameRate = 60; // 限制最大帧率
    self.renderQueue = dispatch_queue_create("com.scrcpy.render", DISPATCH_QUEUE_SERIAL);
    self.frameSemaphore = dispatch_semaphore_create(3); // 限制同时进行的帧处理数量
    self.texturePool = [NSMutableArray array];
    self.isRendering = NO;
    self.lastFrameTime = 0;
    
    // 创建命令队列
    self.commandQueue = [self.device newCommandQueue];
    
    // 创建纹理缓存
    CVReturn result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &_textureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create texture cache: %d", result);
        return;
    }
    
    // 预编译着色器库
    [self precompileShaders];
    
    // 设置渲染管线
    [self setupRenderPipelines];
    
    // 设置顶点缓冲区
    [self setupVertexBuffer];
    
    self.contentMode = UIViewContentModeScaleAspectFit;
    self.needsVertexUpdate = YES;
    
    // 设置合适的刷新率
    self.preferredFramesPerSecond = self.maxFrameRate;
    
    // 监听内存警告
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMemoryWarning)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
}

- (void)precompileShaders {
    // 预编译着色器以避免运行时编译
    NSString *shaderSource = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "\n"
    "struct VertexIn {\n"
    "    float2 position [[attribute(0)]];\n"
    "    float2 texCoord [[attribute(1)]];\n"
    "};\n"
    "\n"
    "struct VertexOut {\n"
    "    float4 position [[position]];\n"
    "    float2 texCoord;\n"
    "};\n"
    "\n"
    "vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {\n"
    "    VertexOut out;\n"
    "    out.position = float4(in.position, 0.0, 1.0);\n"
    "    out.texCoord = in.texCoord;\n"
    "    return out;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_rgb(VertexOut in [[stage_in]],\n"
    "                             texture2d<float> colorTexture [[texture(0)]]) {\n"
    "    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);\n"
    "    float4 color = colorTexture.sample(textureSampler, in.texCoord);\n"
    "    return float4(color.b, color.g, color.r, color.a);\n"
    "}\n"
    "\n"
    "fragment float4 fragment_yuv(VertexOut in [[stage_in]],\n"
    "                             texture2d<float> yTexture [[texture(0)]],\n"
    "                             texture2d<float> uvTexture [[texture(1)]]) {\n"
    "    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);\n"
    "    \n"
    "    float y = yTexture.sample(textureSampler, in.texCoord).r;\n"
    "    float2 uv = uvTexture.sample(textureSampler, in.texCoord).rg;\n"
    "    \n"
    "    // YUV to RGB conversion matrix (BT.709 video range)\n"
    "    // Y range: [16/255, 235/255], UV range: [16/255, 240/255]\n"
    "    y = (y * 255.0 - 16.0) / 219.0;\n"
    "    float u = (uv.r * 255.0 - 128.0) / 224.0;\n"
    "    float v = (uv.g * 255.0 - 128.0) / 224.0;\n"
    "    \n"
    "    float r = y + 1.5748 * v;\n"
    "    float g = y - 0.1873 * u - 0.4681 * v;\n"
    "    float b = y + 1.8556 * u;\n"
    "    \n"
    "    return float4(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), 1.0);\n"
    "}\n";
    
    NSError *error;
    self.shaderLibrary = [self.device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!self.shaderLibrary) {
        NSLog(@"Failed to precompile shader library: %@", error.localizedDescription);
    }
}

- (void)setupRenderPipelines {
    if (!self.shaderLibrary) {
        NSLog(@"Shader library not available");
        return;
    }
    
    [self setupRGBPipeline];
    [self setupYUVPipeline];
}

- (void)setupRGBPipeline {
    id<MTLFunction> vertexFunction = [self.shaderLibrary newFunctionWithName:@"vertex_main"];
    id<MTLFunction> rgbFragmentFunction = [self.shaderLibrary newFunctionWithName:@"fragment_rgb"];
    
    MTLRenderPipelineDescriptor *rgbPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    rgbPipelineDescriptor.vertexFunction = vertexFunction;
    rgbPipelineDescriptor.fragmentFunction = rgbFragmentFunction;
    rgbPipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    rgbPipelineDescriptor.vertexDescriptor = [self createVertexDescriptor];
    
    NSError *error;
    self.rgbPipelineState = [self.device newRenderPipelineStateWithDescriptor:rgbPipelineDescriptor error:&error];
    if (!self.rgbPipelineState) {
        NSLog(@"Failed to create RGB pipeline state: %@", error.localizedDescription);
    }
}

- (void)setupYUVPipeline {
    id<MTLFunction> vertexFunction = [self.shaderLibrary newFunctionWithName:@"vertex_main"];
    id<MTLFunction> yuvFragmentFunction = [self.shaderLibrary newFunctionWithName:@"fragment_yuv"];
    
    MTLRenderPipelineDescriptor *yuvPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    yuvPipelineDescriptor.vertexFunction = vertexFunction;
    yuvPipelineDescriptor.fragmentFunction = yuvFragmentFunction;
    yuvPipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    yuvPipelineDescriptor.vertexDescriptor = [self createVertexDescriptor];
    
    NSError *error;
    self.yuvPipelineState = [self.device newRenderPipelineStateWithDescriptor:yuvPipelineDescriptor error:&error];
    if (!self.yuvPipelineState) {
        NSLog(@"Failed to create YUV pipeline state: %@", error.localizedDescription);
    }
}

- (MTLVertexDescriptor *)createVertexDescriptor {
    MTLVertexDescriptor *vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = sizeof(vector_float2);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(Vertex);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    return vertexDescriptor;
}

- (void)setupVertexBuffer {
    Vertex vertices[] = {
        {{-1.0f,  1.0f}, {0.0f, 0.0f}},  // 左上
        {{ 1.0f,  1.0f}, {1.0f, 0.0f}},  // 右上
        {{-1.0f, -1.0f}, {0.0f, 1.0f}},  // 左下
        {{ 1.0f, -1.0f}, {1.0f, 1.0f}}   // 右下
    };
    
    self.vertexBuffer = [self.device newBufferWithBytes:vertices
                                                  length:sizeof(vertices)
                                                 options:MTLResourceStorageModeShared];
}

- (void)updateVertexBufferForContentMode {
    if (CGSizeEqualToSize(self.videoSize, CGSizeZero) || CGSizeEqualToSize(self.drawableSize, CGSizeZero)) {
        return;
    }
    
    // 检查是否真的需要更新
    if (!self.needsVertexUpdate && CGSizeEqualToSize(self.lastDrawableSize, self.drawableSize)) {
        return;
    }
    
    CGSize viewSize = CGSizeMake(self.drawableSize.width, self.drawableSize.height);
    CGSize videoSize = self.videoSize;
    
    float scaleX = 1.0f;
    float scaleY = 1.0f;
    
    if (self.contentMode == UIViewContentModeScaleAspectFit) {
        float viewAspect = viewSize.width / viewSize.height;
        float videoAspect = videoSize.width / videoSize.height;
        
        if (videoAspect > viewAspect) {
            scaleY = viewAspect / videoAspect;
        } else {
            scaleX = videoAspect / viewAspect;
        }
    } else if (self.contentMode == UIViewContentModeScaleAspectFill) {
        float viewAspect = viewSize.width / viewSize.height;
        float videoAspect = videoSize.width / videoSize.height;
        
        if (videoAspect > viewAspect) {
            scaleX = videoAspect / viewAspect;
        } else {
            scaleY = viewAspect / videoAspect;
        }
    }
    
    Vertex vertices[] = {
        {{-scaleX,  scaleY}, {0.0f, 0.0f}},  // 左上
        {{ scaleX,  scaleY}, {1.0f, 0.0f}},  // 右上
        {{-scaleX, -scaleY}, {0.0f, 1.0f}},  // 左下
        {{ scaleX, -scaleY}, {1.0f, 1.0f}}   // 右下
    };
    
    // 重用现有buffer内容而不是创建新的
    if (self.vertexBuffer) {
        memcpy([self.vertexBuffer contents], vertices, sizeof(vertices));
    } else {
        self.vertexBuffer = [self.device newBufferWithBytes:vertices
                                                      length:sizeof(vertices)
                                                     options:MTLResourceStorageModeShared];
    }
    
    self.needsVertexUpdate = NO;
    self.lastDrawableSize = self.drawableSize;
}

#pragma mark - Helper Methods

- (NSString *)pixelFormatToString:(OSType)pixelFormat {
    char formatStr[5];
    formatStr[0] = (pixelFormat >> 24) & 0xFF;
    formatStr[1] = (pixelFormat >> 16) & 0xFF;
    formatStr[2] = (pixelFormat >> 8) & 0xFF;
    formatStr[3] = pixelFormat & 0xFF;
    formatStr[4] = '\0';
    return [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding];
}

- (BOOL)shouldSkipFrame {
    // 帧率控制：检查是否应该跳过当前帧
    CFTimeInterval currentTime = CACurrentMediaTime();
    CFTimeInterval timeSinceLastFrame = currentTime - self.lastFrameTime;
    CFTimeInterval minFrameInterval = 1.0 / self.maxFrameRate;
    
    if (timeSinceLastFrame < minFrameInterval) {
        return YES;
    }
    
    self.lastFrameTime = currentTime;
    return NO;
}

#pragma mark - Public Methods

- (void)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        return;
    }
    
    // 帧率控制
    if ([self shouldSkipFrame]) {
        return;
    }
    
    // 限制并发渲染数量
    if (dispatch_semaphore_wait(self.frameSemaphore, DISPATCH_TIME_NOW) != 0) {
        // 如果无法获取信号量，跳过这一帧
        return;
    }
    
    // 在后台队列处理纹理创建
    dispatch_async(self.renderQueue, ^{
        @autoreleasepool {
            BOOL success = [self processPixelBuffer:pixelBuffer];
            
            if (success) {
                // 在主线程触发重绘，但不等待
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!self.isRendering) {
                        self.isRendering = YES;
                        [self setNeedsDisplay];
                    }
                });
            }
            
            dispatch_semaphore_signal(self.frameSemaphore);
        }
    });
}

- (BOOL)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    // 检查像素格式
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    
    // 更新视频尺寸
    CGSize newVideoSize = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer),
                                    CVPixelBufferGetHeight(pixelBuffer));
    if (!CGSizeEqualToSize(self.videoSize, newVideoSize)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.videoSize = newVideoSize;
            self.needsVertexUpdate = YES;
        });
    }
    
    BOOL success = NO;
    
    switch (pixelFormat) {
        case kCVPixelFormatType_32BGRA:
        case kCVPixelFormatType_32RGBA:
            success = [self createRGBTextureFromPixelBuffer:pixelBuffer pixelFormat:pixelFormat];
            self.isYUVFormat = NO;
            break;
            
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            success = [self createYUVTexturesFromPixelBuffer:pixelBuffer];
            self.isYUVFormat = YES;
            break;
            
        default:
            NSLog(@"Unsupported pixel format: %d (0x%x) '%@'", pixelFormat, pixelFormat, [self pixelFormatToString:pixelFormat]);
            return NO;
    }
    
    if (success) {
        // 定期清理纹理缓存，但不是每次都清理
        static NSInteger frameCount = 0;
        if (++frameCount % 30 == 0) { // 每30帧清理一次
            CVMetalTextureCacheFlush(self.textureCache, 0);
        }
    }
    
    return success;
}

- (BOOL)createRGBTextureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer pixelFormat:(OSType)pixelFormat {
    MTLPixelFormat metalPixelFormat;
    
    switch (pixelFormat) {
        case kCVPixelFormatType_32BGRA:
            metalPixelFormat = MTLPixelFormatBGRA8Unorm;
            break;
        case kCVPixelFormatType_32RGBA:
            metalPixelFormat = MTLPixelFormatRGBA8Unorm;
            break;
        default:
            return NO;
    }
    
    CVMetalTextureRef textureRef = NULL;
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               self.textureCache,
                                                               pixelBuffer,
                                                               NULL,
                                                               metalPixelFormat,
                                                               CVPixelBufferGetWidth(pixelBuffer),
                                                               CVPixelBufferGetHeight(pixelBuffer),
                                                               0,
                                                               &textureRef);
    
    if (result == kCVReturnSuccess && textureRef) {
        self.currentTexture = CVMetalTextureGetTexture(textureRef);
        CFRelease(textureRef);
        return YES;
    } else {
        NSLog(@"Failed to create RGB texture: %d", result);
        return NO;
    }
}

- (BOOL)createYUVTexturesFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    // 创建 Y 纹理 (plane 0)
    CVMetalTextureRef yTextureRef = NULL;
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               self.textureCache,
                                                               pixelBuffer,
                                                               NULL,
                                                               MTLPixelFormatR8Unorm,
                                                               width,
                                                               height,
                                                               0,  // plane 0 (Y)
                                                               &yTextureRef);
    
    if (result != kCVReturnSuccess || !yTextureRef) {
        NSLog(@"Failed to create Y texture: %d", result);
        return NO;
    }
    
    // 创建 UV 纹理 (plane 1)
    CVMetalTextureRef uvTextureRef = NULL;
    result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                      self.textureCache,
                                                      pixelBuffer,
                                                      NULL,
                                                      MTLPixelFormatRG8Unorm,
                                                      width / 2,
                                                      height / 2,
                                                      1,  // plane 1 (UV)
                                                      &uvTextureRef);
    
    if (result != kCVReturnSuccess || !uvTextureRef) {
        NSLog(@"Failed to create UV texture: %d", result);
        CFRelease(yTextureRef);
        return NO;
    }
    
    self.currentYTexture = CVMetalTextureGetTexture(yTextureRef);
    self.currentUVTexture = CVMetalTextureGetTexture(uvTextureRef);
    
    CFRelease(yTextureRef);
    CFRelease(uvTextureRef);
    
    return YES;
}

- (void)clear {
    dispatch_async(self.renderQueue, ^{
        self.currentTexture = nil;
        self.currentYTexture = nil;
        self.currentUVTexture = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setNeedsDisplay];
        });
    });
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    if (_contentMode != contentMode) {
        _contentMode = contentMode;
        self.needsVertexUpdate = YES;
        [self setNeedsDisplay];
    }
}

- (void)setMaxFrameRate:(NSInteger)maxFrameRate {
    _maxFrameRate = MIN(120, MAX(1, maxFrameRate)); // 限制在1-120之间
    self.preferredFramesPerSecond = _maxFrameRate;
}

- (BOOL)isCurrentlyRendering {
    return self.isRendering;
}

- (void)flushTextureCache {
    if (self.textureCache) {
        CVMetalTextureCacheFlush(self.textureCache, 0);
    }
}

- (CGSize)currentVideoSize {
    return self.videoSize;
}

#pragma mark - Performance Monitoring

- (void)logPerformanceStats {
    // 可选：添加性能监控日志
    static NSInteger frameCount = 0;
    static CFTimeInterval startTime = 0;
    
    if (startTime == 0) {
        startTime = CACurrentMediaTime();
    }
    
    frameCount++;
    if (frameCount % 60 == 0) { // 每60帧打印一次统计
        CFTimeInterval currentTime = CACurrentMediaTime();
        CFTimeInterval elapsed = currentTime - startTime;
        double fps = frameCount / elapsed;
        
        NSLog(@"ScrcpyMetalView Performance: %.1f FPS, Video Size: %.0fx%.0f", 
              fps, self.videoSize.width, self.videoSize.height);
        
        frameCount = 0;
        startTime = currentTime;
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    self.needsVertexUpdate = YES;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.needsVertexUpdate = YES;
}

- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        self.isRendering = NO; // 重置渲染标志
        
        // 可选：性能监控（在调试时启用）
        #ifdef DEBUG
        [self logPerformanceStats];
        #endif
        
        id<MTLRenderPipelineState> pipelineState;
        BOOL hasTextures = NO;
        
        if (self.isYUVFormat) {
            pipelineState = self.yuvPipelineState;
            hasTextures = (self.currentYTexture && self.currentUVTexture);
        } else {
            pipelineState = self.rgbPipelineState;
            hasTextures = (self.currentTexture != nil);
        }
        
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        if (!commandBuffer) {
            return;
        }
        
        // 设置标签用于调试
        commandBuffer.label = @"ScrcpyRenderCommand";
        
        MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
        if (!renderPassDescriptor) {
            return;
        }
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        if (!renderEncoder) {
            return;
        }
        
        renderEncoder.label = @"ScrcpyRenderEncoder";
        
        if (!hasTextures || !pipelineState) {
            // 只清空屏幕，不渲染纹理
            [renderEncoder endEncoding];
            if (view.currentDrawable) {
                [commandBuffer presentDrawable:view.currentDrawable];
            }
            [commandBuffer commit];
            return;
        }
        
        // 更新顶点缓冲区
        if (self.needsVertexUpdate) {
            [self updateVertexBufferForContentMode];
        }
        
        [renderEncoder setRenderPipelineState:pipelineState];
        [renderEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
        
        if (self.isYUVFormat) {
            [renderEncoder setFragmentTexture:self.currentYTexture atIndex:0];
            [renderEncoder setFragmentTexture:self.currentUVTexture atIndex:1];
        } else {
            [renderEncoder setFragmentTexture:self.currentTexture atIndex:0];
        }
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderEncoder endEncoding];
        
        if (view.currentDrawable) {
            [commandBuffer presentDrawable:view.currentDrawable];
        }
        
        [commandBuffer commit];
    }
}

- (void)handleMemoryWarning {
    // 处理内存警告：释放可能的资源
    NSLog(@"ScrcpyMetalView received memory warning, cleaning up resources");
    
    dispatch_async(self.renderQueue, ^{
        // 强制清理纹理缓存
        if (self.textureCache) {
            CVMetalTextureCacheFlush(self.textureCache, 0);
        }
        
        // 清理纹理池
        [self.texturePool removeAllObjects];
        
        // 暂时清理当前纹理引用（下一帧会重新创建）
        self.currentTexture = nil;
        self.currentYTexture = nil;
        self.currentUVTexture = nil;
    });
}

@end
