# Yolox Person Detection - C++ NPU Application Design

## 1. Overview

This document describes the design of a C++ command-line application that performs person detection on JPEG images using the Yolox object detection model running on the Rockchip NPU (Neural Processing Unit).

### 1.1 Requirements

- **Input**: JPEG image file path provided as command-line argument
- **Output**: Count of detected people in the image
- **Detection Criteria**: Person class detections with confidence ≥ 0.80
- **Platform**: Rockchip SoC with NPU support (RK3588/RK3566/RK3568)
- **Language**: C++ only (no Python)
- **Model**: Yolox object detection model

## 2. System Architecture

### 2.1 Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Main Application                          │
│  (yolox_person_detector)                                     │
└───┬─────────────────────────────────────────────────────┬───┘
    │                                                       │
    ▼                                                       ▼
┌─────────────────────┐                        ┌──────────────────────┐
│  Image Loader       │                        │  Argument Parser     │
│  - JPEG decoding    │                        │  - Validate input    │
│  - Format conversion│                        │  - Parse options     │
└──────┬──────────────┘                        └──────────────────────┘
       │
       ▼
┌─────────────────────┐
│  Preprocessor       │
│  - Resize image     │
│  - Normalize        │
│  - Convert to RGB   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│  RKNN Inference     │
│  Engine             │
│  - Load model       │
│  - Execute NPU      │
│  - Get outputs      │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│  Postprocessor      │
│  - Decode boxes     │
│  - Apply NMS        │
│  - Filter by class  │
│  - Filter by conf   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│  Person Counter     │
│  - Count persons    │
│  - Output result    │
└─────────────────────┘
```

### 2.2 Dependencies

1. **RKNN Toolkit Lite C API** (`librknnrt.so`)
   - Runtime library for NPU inference
   - Provides `rknn_init`, `rknn_inputs_set`, `rknn_run`, `rknn_outputs_get`

2. **Image Processing Libraries**
   - **OpenCV** (optional) or **stb_image** (lightweight alternative)
   - JPEG decoding and image manipulation

3. **Standard C++ Libraries**
   - `<iostream>`, `<vector>`, `<string>`, `<algorithm>`, `<cmath>`

## 3. Detailed Design

### 3.1 Input Processing

#### 3.1.1 Command-Line Interface

```cpp
Usage: yolox_person_detector <image_path> [options]

Options:
  -m, --model <path>        Path to RKNN model file (default: yolox_s.rknn)
  -c, --confidence <float>  Confidence threshold (default: 0.80)
  -v, --verbose             Enable verbose output
  -h, --help                Show help message

Example:
  ./yolox_person_detector photo.jpg
  ./yolox_person_detector photo.jpg --model yolox_m.rknn --confidence 0.85
```

#### 3.1.2 Image Loading

- Load JPEG file using stb_image or OpenCV's `cv::imread()`
- Verify image loaded successfully
- Extract dimensions (width, height, channels)

### 3.2 Preprocessing

Yolox typically requires specific input preprocessing:

1. **Resize**: Scale image to model input size (e.g., 640x640)
   - Maintain aspect ratio with letterboxing (add gray padding)
   - Store scaling factors for postprocessing

2. **Color Space**: Ensure RGB format (JPEG may be BGR in some libraries)

3. **Normalization**: No normalization for Yolox (uses raw pixel values 0-255)

4. **Format**: Convert to NHWC or NCHW format as required by model

```cpp
struct PreprocessResult {
    std::vector<uint8_t> data;  // Preprocessed image data
    float scale_w;               // Width scaling factor
    float scale_h;               // Height scaling factor
    int pad_w;                   // Width padding
    int pad_h;                   // Height padding
};
```

### 3.3 RKNN Inference Engine

#### 3.3.1 Model Loading

```cpp
class RKNNInference {
private:
    rknn_context ctx;
    rknn_input_output_num io_num;
    rknn_tensor_attr* input_attrs;
    rknn_tensor_attr* output_attrs;

public:
    bool init(const char* model_path);
    bool run_inference(const uint8_t* input_data);
    void get_outputs(std::vector<float*>& outputs);
    void cleanup();
};
```

#### 3.3.2 Inference Steps

1. **Load Model**: `rknn_init()` with model file path
2. **Query Model Info**: Get input/output tensor attributes
3. **Prepare Input**: Create `rknn_input` structure with preprocessed data
4. **Set Input**: `rknn_inputs_set()`
5. **Execute**: `rknn_run()`
6. **Get Output**: `rknn_outputs_get()`
7. **Release**: `rknn_outputs_release()`

### 3.4 Postprocessing

#### 3.4.1 Yolox Output Format

Yolox outputs a tensor with shape `[1, N, 85]` where:
- N = number of anchor boxes (e.g., 8400 for 640x640 input)
- 85 = [x, y, w, h, objectness, 80 class scores]

For COCO dataset:
- Class 0 = "person"
- Classes 1-79 = other objects

#### 3.4.2 Decoding Process

```cpp
struct Detection {
    float x, y, w, h;        // Bounding box
    float confidence;         // Detection confidence
    int class_id;            // Class ID
};

std::vector<Detection> decode_yolox_output(
    const float* output,
    int num_boxes,
    float conf_threshold,
    float scale_w,
    float scale_h,
    int pad_w,
    int pad_h
);
```

Steps:
1. Iterate through all anchor boxes
2. Calculate final confidence: `objectness * class_score`
3. Filter boxes with confidence < 0.80
4. Filter boxes where class_id != 0 (not person)
5. Transform coordinates back to original image space:
   ```cpp
   x = (x - pad_w) / scale_w
   y = (y - pad_h) / scale_h
   w = w / scale_w
   h = h / scale_h
   ```

#### 3.4.3 Non-Maximum Suppression (NMS)

Apply NMS to remove duplicate detections:
- IoU threshold: 0.45 (typical for Yolox)
- Sort by confidence descending
- Remove overlapping boxes

```cpp
std::vector<Detection> apply_nms(
    std::vector<Detection>& boxes,
    float iou_threshold = 0.45
);
```

### 3.5 Person Counting

After NMS, count remaining detections with:
- `class_id == 0` (person class)
- `confidence >= 0.80`

Output format:
```
Detected X person(s) in the image.
```

If verbose mode is enabled:
```
Person 1: confidence=0.92, box=[x,y,w,h]
Person 2: confidence=0.87, box=[x,y,w,h]
...
Total: X person(s)
```

## 4. File Structure

```
project/
├── CMakeLists.txt
├── src/
│   ├── main.cpp                 # Entry point, CLI parsing
│   ├── image_loader.cpp         # JPEG loading
│   ├── image_loader.h
│   ├── preprocessor.cpp         # Image preprocessing
│   ├── preprocessor.h
│   ├── rknn_inference.cpp       # RKNN engine wrapper
│   ├── rknn_inference.h
│   ├── postprocessor.cpp        # Yolox output decoding, NMS
│   ├── postprocessor.h
│   └── utils.h                  # Common utilities, structs
├── include/
│   └── stb_image.h              # Header-only JPEG decoder (if not using OpenCV)
├── models/
│   └── yolox_s.rknn             # Converted RKNN model
└── test_images/
    └── sample.jpg
```

## 5. Build System

### 5.1 CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.10)
project(yolox_person_detector)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find RKNN library
find_library(RKNN_RT_LIB rknnrt HINTS /usr/lib)
if(NOT RKNN_RT_LIB)
    message(FATAL_ERROR "RKNN runtime library not found")
endif()

# Option to use OpenCV or stb_image
option(USE_OPENCV "Use OpenCV for image loading" OFF)

# Source files
set(SOURCES
    src/main.cpp
    src/image_loader.cpp
    src/preprocessor.cpp
    src/rknn_inference.cpp
    src/postprocessor.cpp
)

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(/usr/include/rknn)  # RKNN headers

add_executable(yolox_person_detector ${SOURCES})

# Link libraries
target_link_libraries(yolox_person_detector ${RKNN_RT_LIB})

if(USE_OPENCV)
    find_package(OpenCV REQUIRED)
    target_link_libraries(yolox_person_detector ${OpenCV_LIBS})
    target_compile_definitions(yolox_person_detector PRIVATE USE_OPENCV)
else()
    # stb_image is header-only, just define the implementation
    target_compile_definitions(yolox_person_detector PRIVATE STB_IMAGE_IMPLEMENTATION)
endif()
```

### 5.2 Build Instructions

```bash
mkdir build
cd build
cmake ..
make
```

## 6. Model Preparation

### 6.1 Obtaining Yolox RKNN Model

The Yolox model must be converted to RKNN format:

1. **Source**: Start with Yolox ONNX model (e.g., `yolox_s.onnx`)
2. **Conversion**: Use RKNN-Toolkit2 Python tools:
   ```bash
   # On x86 development machine
   python3 convert_onnx_to_rknn.py \
       --model yolox_s.onnx \
       --output yolox_s.rknn \
       --target_platform rk3588
   ```
3. **Quantization**: Optional INT8 quantization for better performance
4. **Transfer**: Copy `yolox_s.rknn` to target board

### 6.2 Model Variants

- **yolox-nano**: Fastest, least accurate
- **yolox-tiny**: Fast, good for real-time
- **yolox-s**: Balanced (recommended)
- **yolox-m**: More accurate, slower
- **yolox-l/x**: Highest accuracy, slowest

## 7. Error Handling

### 7.1 Error Cases

1. **Invalid Arguments**
   - Missing image path → Print usage, exit code 1
   - File not found → Error message, exit code 2

2. **Image Loading Errors**
   - Corrupted JPEG → Error message, exit code 3
   - Unsupported format → Error message, exit code 3

3. **Model Errors**
   - Model file not found → Error message, exit code 4
   - RKNN init failed → Error message, exit code 5
   - Incompatible model format → Error message, exit code 5

4. **Inference Errors**
   - NPU execution failed → Error message, exit code 6
   - Out of memory → Error message, exit code 7

### 7.2 Return Codes

- 0: Success
- 1: Invalid command-line arguments
- 2: File I/O error
- 3: Image processing error
- 4: Model file error
- 5: RKNN initialization error
- 6: Inference error
- 7: Memory error

## 8. Performance Considerations

### 8.1 Optimization Strategies

1. **Model Quantization**: Use INT8 quantized model for ~4x speedup
2. **Input Size**: Smaller input (e.g., 416x416) for faster inference
3. **Memory Management**: Reuse buffers, avoid unnecessary copies
4. **NPU Core**: Utilize multi-core NPU if available (RK3588 has 3 cores)

### 8.2 Expected Performance

On RK3588:
- **Yolox-s (640x640)**: ~30-50ms inference time
- **Yolox-nano (416x416)**: ~10-15ms inference time
- **Total pipeline**: Add ~10-20ms for image loading and postprocessing

## 9. Testing Strategy

### 9.1 Unit Tests

1. **Preprocessor**: Test letterbox resizing, padding calculations
2. **Postprocessor**: Test NMS algorithm, coordinate transformation
3. **Detection Filtering**: Verify confidence and class filtering

### 9.2 Integration Tests

1. **Known Images**: Test with labeled images, verify detection count
2. **Edge Cases**:
   - Empty image (no people) → 0 count
   - Crowd scene → Correct count
   - Low confidence detections → Filtered out
   - Multiple classes → Only count persons

### 9.3 Test Images

Prepare test set:
- `no_person.jpg` → Expected: 0
- `one_person.jpg` → Expected: 1
- `crowd.jpg` → Expected: N (known count)
- `mixed_objects.jpg` → Expected: M (only count people)

## 10. Future Enhancements

1. **Batch Processing**: Process multiple images
2. **Video Support**: Process video files or camera streams
3. **Visualization**: Draw bounding boxes on output image
4. **JSON Output**: Machine-readable output format
5. **Multi-threading**: Parallelize preprocessing/postprocessing
6. **Model Selection**: Runtime model switching

## 11. References

- RKNN Toolkit2 Documentation
- Yolox: Exceeding YOLO Series in 2021 (paper)
- Rockchip NPU SDK API Reference
- COCO Dataset Classes and IDs
