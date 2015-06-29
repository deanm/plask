// Constants from the WebGL specification.
// Designed to be used as an "x-macro".

#ifdef WEBGL_CONSTANTS_EACH
/* ClearBufferMask */
WEBGL_CONSTANTS_EACH(DEPTH_BUFFER_BIT, 0x00000100)
WEBGL_CONSTANTS_EACH(STENCIL_BUFFER_BIT, 0x00000400)
WEBGL_CONSTANTS_EACH(COLOR_BUFFER_BIT, 0x00004000)

/* BeginMode */
WEBGL_CONSTANTS_EACH(POINTS, 0x0000)
WEBGL_CONSTANTS_EACH(LINES, 0x0001)
WEBGL_CONSTANTS_EACH(LINE_LOOP, 0x0002)
WEBGL_CONSTANTS_EACH(LINE_STRIP, 0x0003)
WEBGL_CONSTANTS_EACH(TRIANGLES, 0x0004)
WEBGL_CONSTANTS_EACH(TRIANGLE_STRIP, 0x0005)
WEBGL_CONSTANTS_EACH(TRIANGLE_FAN, 0x0006)

/* AlphaFunction (not supported in ES20) */
/*      NEVER */
/*      LESS */
/*      EQUAL */
/*      LEQUAL */
/*      GREATER */
/*      NOTEQUAL */
/*      GEQUAL */
/*      ALWAYS */

/* BlendingFactorDest */
WEBGL_CONSTANTS_EACH(ZERO, 0)
WEBGL_CONSTANTS_EACH(ONE, 1)
WEBGL_CONSTANTS_EACH(SRC_COLOR, 0x0300)
WEBGL_CONSTANTS_EACH(ONE_MINUS_SRC_COLOR, 0x0301)
WEBGL_CONSTANTS_EACH(SRC_ALPHA, 0x0302)
WEBGL_CONSTANTS_EACH(ONE_MINUS_SRC_ALPHA, 0x0303)
WEBGL_CONSTANTS_EACH(DST_ALPHA, 0x0304)
WEBGL_CONSTANTS_EACH(ONE_MINUS_DST_ALPHA, 0x0305)

/* BlendingFactorSrc */
/*      ZERO */
/*      ONE */
WEBGL_CONSTANTS_EACH(DST_COLOR, 0x0306)
WEBGL_CONSTANTS_EACH(ONE_MINUS_DST_COLOR, 0x0307)
WEBGL_CONSTANTS_EACH(SRC_ALPHA_SATURATE, 0x0308)
/*      SRC_ALPHA */
/*      ONE_MINUS_SRC_ALPHA */
/*      DST_ALPHA */
/*      ONE_MINUS_DST_ALPHA */

/* BlendEquationSeparate */
WEBGL_CONSTANTS_EACH(FUNC_ADD, 0x8006)
WEBGL_CONSTANTS_EACH(BLEND_EQUATION, 0x8009)
WEBGL_CONSTANTS_EACH(BLEND_EQUATION_RGB, 0x8009)   /* same as BLEND_EQUATION */
WEBGL_CONSTANTS_EACH(BLEND_EQUATION_ALPHA, 0x883D)

/* BlendSubtract */
WEBGL_CONSTANTS_EACH(FUNC_SUBTRACT, 0x800A)
WEBGL_CONSTANTS_EACH(FUNC_REVERSE_SUBTRACT, 0x800B)

/* Separate Blend Functions */
WEBGL_CONSTANTS_EACH(BLEND_DST_RGB, 0x80C8)
WEBGL_CONSTANTS_EACH(BLEND_SRC_RGB, 0x80C9)
WEBGL_CONSTANTS_EACH(BLEND_DST_ALPHA, 0x80CA)
WEBGL_CONSTANTS_EACH(BLEND_SRC_ALPHA, 0x80CB)
WEBGL_CONSTANTS_EACH(CONSTANT_COLOR, 0x8001)
WEBGL_CONSTANTS_EACH(ONE_MINUS_CONSTANT_COLOR, 0x8002)
WEBGL_CONSTANTS_EACH(CONSTANT_ALPHA, 0x8003)
WEBGL_CONSTANTS_EACH(ONE_MINUS_CONSTANT_ALPHA, 0x8004)
WEBGL_CONSTANTS_EACH(BLEND_COLOR, 0x8005)

/* Buffer Objects */
WEBGL_CONSTANTS_EACH(ARRAY_BUFFER, 0x8892)
WEBGL_CONSTANTS_EACH(ELEMENT_ARRAY_BUFFER, 0x8893)
WEBGL_CONSTANTS_EACH(ARRAY_BUFFER_BINDING, 0x8894)
WEBGL_CONSTANTS_EACH(ELEMENT_ARRAY_BUFFER_BINDING, 0x8895)

WEBGL_CONSTANTS_EACH(STREAM_DRAW, 0x88E0)
WEBGL_CONSTANTS_EACH(STATIC_DRAW, 0x88E4)
WEBGL_CONSTANTS_EACH(DYNAMIC_DRAW, 0x88E8)

WEBGL_CONSTANTS_EACH(BUFFER_SIZE, 0x8764)
WEBGL_CONSTANTS_EACH(BUFFER_USAGE, 0x8765)

WEBGL_CONSTANTS_EACH(CURRENT_VERTEX_ATTRIB, 0x8626)

/* CullFaceMode */
WEBGL_CONSTANTS_EACH(FRONT, 0x0404)
WEBGL_CONSTANTS_EACH(BACK, 0x0405)
WEBGL_CONSTANTS_EACH(FRONT_AND_BACK, 0x0408)

/* DepthFunction */
/*      NEVER */
/*      LESS */
/*      EQUAL */
/*      LEQUAL */
/*      GREATER */
/*      NOTEQUAL */
/*      GEQUAL */
/*      ALWAYS */

/* EnableCap */
/* TEXTURE_2D */
WEBGL_CONSTANTS_EACH(CULL_FACE, 0x0B44)
WEBGL_CONSTANTS_EACH(BLEND, 0x0BE2)
WEBGL_CONSTANTS_EACH(DITHER, 0x0BD0)
WEBGL_CONSTANTS_EACH(STENCIL_TEST, 0x0B90)
WEBGL_CONSTANTS_EACH(DEPTH_TEST, 0x0B71)
WEBGL_CONSTANTS_EACH(SCISSOR_TEST, 0x0C11)
WEBGL_CONSTANTS_EACH(POLYGON_OFFSET_FILL, 0x8037)
WEBGL_CONSTANTS_EACH(SAMPLE_ALPHA_TO_COVERAGE, 0x809E)
WEBGL_CONSTANTS_EACH(SAMPLE_COVERAGE, 0x80A0)

/* ErrorCode */
WEBGL_CONSTANTS_EACH(NO_ERROR, 0)
WEBGL_CONSTANTS_EACH(INVALID_ENUM, 0x0500)
WEBGL_CONSTANTS_EACH(INVALID_VALUE, 0x0501)
WEBGL_CONSTANTS_EACH(INVALID_OPERATION, 0x0502)
WEBGL_CONSTANTS_EACH(OUT_OF_MEMORY, 0x0505)

/* FrontFaceDirection */
WEBGL_CONSTANTS_EACH(CW, 0x0900)
WEBGL_CONSTANTS_EACH(CCW, 0x0901)

/* GetPName */
WEBGL_CONSTANTS_EACH(LINE_WIDTH, 0x0B21)
WEBGL_CONSTANTS_EACH(ALIASED_POINT_SIZE_RANGE, 0x846D)
WEBGL_CONSTANTS_EACH(ALIASED_LINE_WIDTH_RANGE, 0x846E)
WEBGL_CONSTANTS_EACH(CULL_FACE_MODE, 0x0B45)
WEBGL_CONSTANTS_EACH(FRONT_FACE, 0x0B46)
WEBGL_CONSTANTS_EACH(DEPTH_RANGE, 0x0B70)
WEBGL_CONSTANTS_EACH(DEPTH_WRITEMASK, 0x0B72)
WEBGL_CONSTANTS_EACH(DEPTH_CLEAR_VALUE, 0x0B73)
WEBGL_CONSTANTS_EACH(DEPTH_FUNC, 0x0B74)
WEBGL_CONSTANTS_EACH(STENCIL_CLEAR_VALUE, 0x0B91)
WEBGL_CONSTANTS_EACH(STENCIL_FUNC, 0x0B92)
WEBGL_CONSTANTS_EACH(STENCIL_FAIL, 0x0B94)
WEBGL_CONSTANTS_EACH(STENCIL_PASS_DEPTH_FAIL, 0x0B95)
WEBGL_CONSTANTS_EACH(STENCIL_PASS_DEPTH_PASS, 0x0B96)
WEBGL_CONSTANTS_EACH(STENCIL_REF, 0x0B97)
WEBGL_CONSTANTS_EACH(STENCIL_VALUE_MASK, 0x0B93)
WEBGL_CONSTANTS_EACH(STENCIL_WRITEMASK, 0x0B98)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_FUNC, 0x8800)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_FAIL, 0x8801)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_PASS_DEPTH_FAIL, 0x8802)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_PASS_DEPTH_PASS, 0x8803)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_REF, 0x8CA3)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_VALUE_MASK, 0x8CA4)
WEBGL_CONSTANTS_EACH(STENCIL_BACK_WRITEMASK, 0x8CA5)
WEBGL_CONSTANTS_EACH(VIEWPORT, 0x0BA2)
WEBGL_CONSTANTS_EACH(SCISSOR_BOX, 0x0C10)
/*      SCISSOR_TEST */
WEBGL_CONSTANTS_EACH(COLOR_CLEAR_VALUE, 0x0C22)
WEBGL_CONSTANTS_EACH(COLOR_WRITEMASK, 0x0C23)
WEBGL_CONSTANTS_EACH(UNPACK_ALIGNMENT, 0x0CF5)
WEBGL_CONSTANTS_EACH(PACK_ALIGNMENT, 0x0D05)
WEBGL_CONSTANTS_EACH(MAX_TEXTURE_SIZE, 0x0D33)
WEBGL_CONSTANTS_EACH(MAX_VIEWPORT_DIMS, 0x0D3A)
WEBGL_CONSTANTS_EACH(SUBPIXEL_BITS, 0x0D50)
WEBGL_CONSTANTS_EACH(RED_BITS, 0x0D52)
WEBGL_CONSTANTS_EACH(GREEN_BITS, 0x0D53)
WEBGL_CONSTANTS_EACH(BLUE_BITS, 0x0D54)
WEBGL_CONSTANTS_EACH(ALPHA_BITS, 0x0D55)
WEBGL_CONSTANTS_EACH(DEPTH_BITS, 0x0D56)
WEBGL_CONSTANTS_EACH(STENCIL_BITS, 0x0D57)
WEBGL_CONSTANTS_EACH(POLYGON_OFFSET_UNITS, 0x2A00)
/*      POLYGON_OFFSET_FILL */
WEBGL_CONSTANTS_EACH(POLYGON_OFFSET_FACTOR, 0x8038)
WEBGL_CONSTANTS_EACH(TEXTURE_BINDING_2D, 0x8069)
WEBGL_CONSTANTS_EACH(SAMPLE_BUFFERS, 0x80A8)
WEBGL_CONSTANTS_EACH(SAMPLES, 0x80A9)
WEBGL_CONSTANTS_EACH(SAMPLE_COVERAGE_VALUE, 0x80AA)
WEBGL_CONSTANTS_EACH(SAMPLE_COVERAGE_INVERT, 0x80AB)

/* GetTextureParameter */
/*      TEXTURE_MAG_FILTER */
/*      TEXTURE_MIN_FILTER */
/*      TEXTURE_WRAP_S */
/*      TEXTURE_WRAP_T */

WEBGL_CONSTANTS_EACH(COMPRESSED_TEXTURE_FORMATS, 0x86A3)

/* HintMode */
WEBGL_CONSTANTS_EACH(DONT_CARE, 0x1100)
WEBGL_CONSTANTS_EACH(FASTEST, 0x1101)
WEBGL_CONSTANTS_EACH(NICEST, 0x1102)

/* HintTarget */
WEBGL_CONSTANTS_EACH(GENERATE_MIPMAP_HINT, 0x8192)

/* DataType */
WEBGL_CONSTANTS_EACH(BYTE, 0x1400)
WEBGL_CONSTANTS_EACH(UNSIGNED_BYTE, 0x1401)
WEBGL_CONSTANTS_EACH(SHORT, 0x1402)
WEBGL_CONSTANTS_EACH(UNSIGNED_SHORT, 0x1403)
WEBGL_CONSTANTS_EACH(INT, 0x1404)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT, 0x1405)
WEBGL_CONSTANTS_EACH(FLOAT, 0x1406)

/* PixelFormat */
WEBGL_CONSTANTS_EACH(DEPTH_COMPONENT, 0x1902)
WEBGL_CONSTANTS_EACH(ALPHA, 0x1906)
WEBGL_CONSTANTS_EACH(RGB, 0x1907)
WEBGL_CONSTANTS_EACH(RGBA, 0x1908)
WEBGL_CONSTANTS_EACH(LUMINANCE, 0x1909)
WEBGL_CONSTANTS_EACH(LUMINANCE_ALPHA, 0x190A)

/* PixelType */
/*      UNSIGNED_BYTE */
WEBGL_CONSTANTS_EACH(UNSIGNED_SHORT_4_4_4_4, 0x8033)
WEBGL_CONSTANTS_EACH(UNSIGNED_SHORT_5_5_5_1, 0x8034)
WEBGL_CONSTANTS_EACH(UNSIGNED_SHORT_5_6_5, 0x8363)

/* Shaders */
WEBGL_CONSTANTS_EACH(FRAGMENT_SHADER, 0x8B30)
WEBGL_CONSTANTS_EACH(VERTEX_SHADER, 0x8B31)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_ATTRIBS, 0x8869)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_UNIFORM_VECTORS, 0x8DFB)
WEBGL_CONSTANTS_EACH(MAX_VARYING_VECTORS, 0x8DFC)
WEBGL_CONSTANTS_EACH(MAX_COMBINED_TEXTURE_IMAGE_UNITS, 0x8B4D)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_TEXTURE_IMAGE_UNITS, 0x8B4C)
WEBGL_CONSTANTS_EACH(MAX_TEXTURE_IMAGE_UNITS, 0x8872)
WEBGL_CONSTANTS_EACH(MAX_FRAGMENT_UNIFORM_VECTORS, 0x8DFD)
WEBGL_CONSTANTS_EACH(SHADER_TYPE, 0x8B4F)
WEBGL_CONSTANTS_EACH(DELETE_STATUS, 0x8B80)
WEBGL_CONSTANTS_EACH(LINK_STATUS, 0x8B82)
WEBGL_CONSTANTS_EACH(VALIDATE_STATUS, 0x8B83)
WEBGL_CONSTANTS_EACH(ATTACHED_SHADERS, 0x8B85)
WEBGL_CONSTANTS_EACH(ACTIVE_UNIFORMS, 0x8B86)
WEBGL_CONSTANTS_EACH(ACTIVE_ATTRIBUTES, 0x8B89)
WEBGL_CONSTANTS_EACH(SHADING_LANGUAGE_VERSION, 0x8B8C)
WEBGL_CONSTANTS_EACH(CURRENT_PROGRAM, 0x8B8D)

/* StencilFunction */
WEBGL_CONSTANTS_EACH(NEVER, 0x0200)
WEBGL_CONSTANTS_EACH(LESS, 0x0201)
WEBGL_CONSTANTS_EACH(EQUAL, 0x0202)
WEBGL_CONSTANTS_EACH(LEQUAL, 0x0203)
WEBGL_CONSTANTS_EACH(GREATER, 0x0204)
WEBGL_CONSTANTS_EACH(NOTEQUAL, 0x0205)
WEBGL_CONSTANTS_EACH(GEQUAL, 0x0206)
WEBGL_CONSTANTS_EACH(ALWAYS, 0x0207)

/* StencilOp */
/*      ZERO */
WEBGL_CONSTANTS_EACH(KEEP, 0x1E00)
WEBGL_CONSTANTS_EACH(REPLACE, 0x1E01)
WEBGL_CONSTANTS_EACH(INCR, 0x1E02)
WEBGL_CONSTANTS_EACH(DECR, 0x1E03)
WEBGL_CONSTANTS_EACH(INVERT, 0x150A)
WEBGL_CONSTANTS_EACH(INCR_WRAP, 0x8507)
WEBGL_CONSTANTS_EACH(DECR_WRAP, 0x8508)

/* StringName */
WEBGL_CONSTANTS_EACH(VENDOR, 0x1F00)
WEBGL_CONSTANTS_EACH(RENDERER, 0x1F01)
WEBGL_CONSTANTS_EACH(VERSION, 0x1F02)

/* TextureMagFilter */
WEBGL_CONSTANTS_EACH(NEAREST, 0x2600)
WEBGL_CONSTANTS_EACH(LINEAR, 0x2601)

/* TextureMinFilter */
/*      NEAREST */
/*      LINEAR */
WEBGL_CONSTANTS_EACH(NEAREST_MIPMAP_NEAREST, 0x2700)
WEBGL_CONSTANTS_EACH(LINEAR_MIPMAP_NEAREST, 0x2701)
WEBGL_CONSTANTS_EACH(NEAREST_MIPMAP_LINEAR, 0x2702)
WEBGL_CONSTANTS_EACH(LINEAR_MIPMAP_LINEAR, 0x2703)

/* TextureParameterName */
WEBGL_CONSTANTS_EACH(TEXTURE_MAG_FILTER, 0x2800)
WEBGL_CONSTANTS_EACH(TEXTURE_MIN_FILTER, 0x2801)
WEBGL_CONSTANTS_EACH(TEXTURE_WRAP_S, 0x2802)
WEBGL_CONSTANTS_EACH(TEXTURE_WRAP_T, 0x2803)

/* TextureTarget */
WEBGL_CONSTANTS_EACH(TEXTURE_2D, 0x0DE1)
WEBGL_CONSTANTS_EACH(TEXTURE, 0x1702)

WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP, 0x8513)
WEBGL_CONSTANTS_EACH(TEXTURE_BINDING_CUBE_MAP, 0x8514)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_POSITIVE_X, 0x8515)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_NEGATIVE_X, 0x8516)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_POSITIVE_Y, 0x8517)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_NEGATIVE_Y, 0x8518)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_POSITIVE_Z, 0x8519)
WEBGL_CONSTANTS_EACH(TEXTURE_CUBE_MAP_NEGATIVE_Z, 0x851A)
WEBGL_CONSTANTS_EACH(MAX_CUBE_MAP_TEXTURE_SIZE, 0x851C)

/* TextureUnit */
WEBGL_CONSTANTS_EACH(TEXTURE0, 0x84C0)
WEBGL_CONSTANTS_EACH(TEXTURE1, 0x84C1)
WEBGL_CONSTANTS_EACH(TEXTURE2, 0x84C2)
WEBGL_CONSTANTS_EACH(TEXTURE3, 0x84C3)
WEBGL_CONSTANTS_EACH(TEXTURE4, 0x84C4)
WEBGL_CONSTANTS_EACH(TEXTURE5, 0x84C5)
WEBGL_CONSTANTS_EACH(TEXTURE6, 0x84C6)
WEBGL_CONSTANTS_EACH(TEXTURE7, 0x84C7)
WEBGL_CONSTANTS_EACH(TEXTURE8, 0x84C8)
WEBGL_CONSTANTS_EACH(TEXTURE9, 0x84C9)
WEBGL_CONSTANTS_EACH(TEXTURE10, 0x84CA)
WEBGL_CONSTANTS_EACH(TEXTURE11, 0x84CB)
WEBGL_CONSTANTS_EACH(TEXTURE12, 0x84CC)
WEBGL_CONSTANTS_EACH(TEXTURE13, 0x84CD)
WEBGL_CONSTANTS_EACH(TEXTURE14, 0x84CE)
WEBGL_CONSTANTS_EACH(TEXTURE15, 0x84CF)
WEBGL_CONSTANTS_EACH(TEXTURE16, 0x84D0)
WEBGL_CONSTANTS_EACH(TEXTURE17, 0x84D1)
WEBGL_CONSTANTS_EACH(TEXTURE18, 0x84D2)
WEBGL_CONSTANTS_EACH(TEXTURE19, 0x84D3)
WEBGL_CONSTANTS_EACH(TEXTURE20, 0x84D4)
WEBGL_CONSTANTS_EACH(TEXTURE21, 0x84D5)
WEBGL_CONSTANTS_EACH(TEXTURE22, 0x84D6)
WEBGL_CONSTANTS_EACH(TEXTURE23, 0x84D7)
WEBGL_CONSTANTS_EACH(TEXTURE24, 0x84D8)
WEBGL_CONSTANTS_EACH(TEXTURE25, 0x84D9)
WEBGL_CONSTANTS_EACH(TEXTURE26, 0x84DA)
WEBGL_CONSTANTS_EACH(TEXTURE27, 0x84DB)
WEBGL_CONSTANTS_EACH(TEXTURE28, 0x84DC)
WEBGL_CONSTANTS_EACH(TEXTURE29, 0x84DD)
WEBGL_CONSTANTS_EACH(TEXTURE30, 0x84DE)
WEBGL_CONSTANTS_EACH(TEXTURE31, 0x84DF)
WEBGL_CONSTANTS_EACH(ACTIVE_TEXTURE, 0x84E0)

/* TextureWrapMode */
WEBGL_CONSTANTS_EACH(REPEAT, 0x2901)
WEBGL_CONSTANTS_EACH(CLAMP_TO_EDGE, 0x812F)
WEBGL_CONSTANTS_EACH(MIRRORED_REPEAT, 0x8370)

/* Uniform Types */
WEBGL_CONSTANTS_EACH(FLOAT_VEC2, 0x8B50)
WEBGL_CONSTANTS_EACH(FLOAT_VEC3, 0x8B51)
WEBGL_CONSTANTS_EACH(FLOAT_VEC4, 0x8B52)
WEBGL_CONSTANTS_EACH(INT_VEC2, 0x8B53)
WEBGL_CONSTANTS_EACH(INT_VEC3, 0x8B54)
WEBGL_CONSTANTS_EACH(INT_VEC4, 0x8B55)
WEBGL_CONSTANTS_EACH(BOOL, 0x8B56)
WEBGL_CONSTANTS_EACH(BOOL_VEC2, 0x8B57)
WEBGL_CONSTANTS_EACH(BOOL_VEC3, 0x8B58)
WEBGL_CONSTANTS_EACH(BOOL_VEC4, 0x8B59)
WEBGL_CONSTANTS_EACH(FLOAT_MAT2, 0x8B5A)
WEBGL_CONSTANTS_EACH(FLOAT_MAT3, 0x8B5B)
WEBGL_CONSTANTS_EACH(FLOAT_MAT4, 0x8B5C)
WEBGL_CONSTANTS_EACH(SAMPLER_2D, 0x8B5E)
WEBGL_CONSTANTS_EACH(SAMPLER_CUBE, 0x8B60)

/* Vertex Arrays */
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_ENABLED, 0x8622)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_SIZE, 0x8623)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_STRIDE, 0x8624)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_TYPE, 0x8625)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_NORMALIZED, 0x886A)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_POINTER, 0x8645)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, 0x889F)

/* Read Format */
WEBGL_CONSTANTS_EACH(IMPLEMENTATION_COLOR_READ_TYPE, 0x8B9A)
WEBGL_CONSTANTS_EACH(IMPLEMENTATION_COLOR_READ_FORMAT, 0x8B9B)

/* Shader Source */
WEBGL_CONSTANTS_EACH(COMPILE_STATUS, 0x8B81)

/* Shader Precision-Specified Types */
WEBGL_CONSTANTS_EACH(LOW_FLOAT, 0x8DF0)
WEBGL_CONSTANTS_EACH(MEDIUM_FLOAT, 0x8DF1)
WEBGL_CONSTANTS_EACH(HIGH_FLOAT, 0x8DF2)
WEBGL_CONSTANTS_EACH(LOW_INT, 0x8DF3)
WEBGL_CONSTANTS_EACH(MEDIUM_INT, 0x8DF4)
WEBGL_CONSTANTS_EACH(HIGH_INT, 0x8DF5)

/* Framebuffer Object. */
WEBGL_CONSTANTS_EACH(FRAMEBUFFER, 0x8D40)
WEBGL_CONSTANTS_EACH(RENDERBUFFER, 0x8D41)

WEBGL_CONSTANTS_EACH(RGBA4, 0x8056)
WEBGL_CONSTANTS_EACH(RGB5_A1, 0x8057)
WEBGL_CONSTANTS_EACH(RGB565, 0x8D62)
WEBGL_CONSTANTS_EACH(DEPTH_COMPONENT16, 0x81A5)
WEBGL_CONSTANTS_EACH(STENCIL_INDEX, 0x1901)
WEBGL_CONSTANTS_EACH(STENCIL_INDEX8, 0x8D48)
WEBGL_CONSTANTS_EACH(DEPTH_STENCIL, 0x84F9)

WEBGL_CONSTANTS_EACH(RENDERBUFFER_WIDTH, 0x8D42)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_HEIGHT, 0x8D43)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_INTERNAL_FORMAT, 0x8D44)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_RED_SIZE, 0x8D50)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_GREEN_SIZE, 0x8D51)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_BLUE_SIZE, 0x8D52)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_ALPHA_SIZE, 0x8D53)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_DEPTH_SIZE, 0x8D54)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_STENCIL_SIZE, 0x8D55)

WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, 0x8CD0)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, 0x8CD1)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL, 0x8CD2)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE, 0x8CD3)

WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT0, 0x8CE0)
WEBGL_CONSTANTS_EACH(DEPTH_ATTACHMENT, 0x8D00)
WEBGL_CONSTANTS_EACH(STENCIL_ATTACHMENT, 0x8D20)
WEBGL_CONSTANTS_EACH(DEPTH_STENCIL_ATTACHMENT, 0x821A)

WEBGL_CONSTANTS_EACH(NONE, 0)

WEBGL_CONSTANTS_EACH(FRAMEBUFFER_COMPLETE, 0x8CD5)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_INCOMPLETE_ATTACHMENT, 0x8CD6)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT, 0x8CD7)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_INCOMPLETE_DIMENSIONS, 0x8CD9)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_UNSUPPORTED, 0x8CDD)

WEBGL_CONSTANTS_EACH(FRAMEBUFFER_BINDING, 0x8CA6)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_BINDING, 0x8CA7)
WEBGL_CONSTANTS_EACH(MAX_RENDERBUFFER_SIZE, 0x84E8)

WEBGL_CONSTANTS_EACH(INVALID_FRAMEBUFFER_OPERATION, 0x0506)

/* WebGL-specific enums */
WEBGL_CONSTANTS_EACH(UNPACK_FLIP_Y_WEBGL, 0x9240)
WEBGL_CONSTANTS_EACH(UNPACK_PREMULTIPLY_ALPHA_WEBGL, 0x9241)
WEBGL_CONSTANTS_EACH(CONTEXT_LOST_WEBGL, 0x9242)
WEBGL_CONSTANTS_EACH(UNPACK_COLORSPACE_CONVERSION_WEBGL, 0x9243)
WEBGL_CONSTANTS_EACH(BROWSER_DEFAULT_WEBGL, 0x9244)

// WebGL 2.0
WEBGL_CONSTANTS_EACH(READ_BUFFER, 0x0C02)
WEBGL_CONSTANTS_EACH(UNPACK_ROW_LENGTH, 0x0CF2)
WEBGL_CONSTANTS_EACH(UNPACK_SKIP_ROWS, 0x0CF3)
WEBGL_CONSTANTS_EACH(UNPACK_SKIP_PIXELS, 0x0CF4)
WEBGL_CONSTANTS_EACH(PACK_ROW_LENGTH, 0x0D02)
WEBGL_CONSTANTS_EACH(PACK_SKIP_ROWS, 0x0D03)
WEBGL_CONSTANTS_EACH(PACK_SKIP_PIXELS, 0x0D04)
WEBGL_CONSTANTS_EACH(COLOR, 0x1800)
WEBGL_CONSTANTS_EACH(DEPTH, 0x1801)
WEBGL_CONSTANTS_EACH(STENCIL, 0x1802)
WEBGL_CONSTANTS_EACH(RED, 0x1903)
WEBGL_CONSTANTS_EACH(RGB8, 0x8051)
WEBGL_CONSTANTS_EACH(RGBA8, 0x8058)
WEBGL_CONSTANTS_EACH(RGB10_A2, 0x8059)
WEBGL_CONSTANTS_EACH(TEXTURE_BINDING_3D, 0x806A)
WEBGL_CONSTANTS_EACH(UNPACK_SKIP_IMAGES, 0x806D)
WEBGL_CONSTANTS_EACH(UNPACK_IMAGE_HEIGHT, 0x806E)
WEBGL_CONSTANTS_EACH(TEXTURE_3D, 0x806F)
WEBGL_CONSTANTS_EACH(TEXTURE_WRAP_R, 0x8072)
WEBGL_CONSTANTS_EACH(MAX_3D_TEXTURE_SIZE, 0x8073)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_2_10_10_10_REV, 0x8368)
WEBGL_CONSTANTS_EACH(MAX_ELEMENTS_VERTICES, 0x80E8)
WEBGL_CONSTANTS_EACH(MAX_ELEMENTS_INDICES, 0x80E9)
WEBGL_CONSTANTS_EACH(TEXTURE_MIN_LOD, 0x813A)
WEBGL_CONSTANTS_EACH(TEXTURE_MAX_LOD, 0x813B)
WEBGL_CONSTANTS_EACH(TEXTURE_BASE_LEVEL, 0x813C)
WEBGL_CONSTANTS_EACH(TEXTURE_MAX_LEVEL, 0x813D)
WEBGL_CONSTANTS_EACH(MIN, 0x8007)
WEBGL_CONSTANTS_EACH(MAX, 0x8008)
WEBGL_CONSTANTS_EACH(DEPTH_COMPONENT24, 0x81A6)
WEBGL_CONSTANTS_EACH(MAX_TEXTURE_LOD_BIAS, 0x84FD)
WEBGL_CONSTANTS_EACH(TEXTURE_COMPARE_MODE, 0x884C)
WEBGL_CONSTANTS_EACH(TEXTURE_COMPARE_FUNC, 0x884D)
WEBGL_CONSTANTS_EACH(CURRENT_QUERY, 0x8865)
WEBGL_CONSTANTS_EACH(QUERY_RESULT, 0x8866)
WEBGL_CONSTANTS_EACH(QUERY_RESULT_AVAILABLE, 0x8867)
WEBGL_CONSTANTS_EACH(STREAM_READ, 0x88E1)
WEBGL_CONSTANTS_EACH(STREAM_COPY, 0x88E2)
WEBGL_CONSTANTS_EACH(STATIC_READ, 0x88E5)
WEBGL_CONSTANTS_EACH(STATIC_COPY, 0x88E6)
WEBGL_CONSTANTS_EACH(DYNAMIC_READ, 0x88E9)
WEBGL_CONSTANTS_EACH(DYNAMIC_COPY, 0x88EA)
WEBGL_CONSTANTS_EACH(MAX_DRAW_BUFFERS, 0x8824)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER0, 0x8825)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER1, 0x8826)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER2, 0x8827)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER3, 0x8828)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER4, 0x8829)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER5, 0x882A)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER6, 0x882B)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER7, 0x882C)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER8, 0x882D)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER9, 0x882E)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER10, 0x882F)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER11, 0x8830)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER12, 0x8831)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER13, 0x8832)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER14, 0x8833)
WEBGL_CONSTANTS_EACH(DRAW_BUFFER15, 0x8834)
WEBGL_CONSTANTS_EACH(MAX_FRAGMENT_UNIFORM_COMPONENTS, 0x8B49)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_UNIFORM_COMPONENTS, 0x8B4A)
WEBGL_CONSTANTS_EACH(SAMPLER_3D, 0x8B5F)
WEBGL_CONSTANTS_EACH(SAMPLER_2D_SHADOW, 0x8B62)
WEBGL_CONSTANTS_EACH(FRAGMENT_SHADER_DERIVATIVE_HINT, 0x8B8B)
WEBGL_CONSTANTS_EACH(PIXEL_PACK_BUFFER, 0x88EB)
WEBGL_CONSTANTS_EACH(PIXEL_UNPACK_BUFFER, 0x88EC)
WEBGL_CONSTANTS_EACH(PIXEL_PACK_BUFFER_BINDING, 0x88ED)
WEBGL_CONSTANTS_EACH(PIXEL_UNPACK_BUFFER_BINDING, 0x88EF)
WEBGL_CONSTANTS_EACH(FLOAT_MAT2x3, 0x8B65)
WEBGL_CONSTANTS_EACH(FLOAT_MAT2x4, 0x8B66)
WEBGL_CONSTANTS_EACH(FLOAT_MAT3x2, 0x8B67)
WEBGL_CONSTANTS_EACH(FLOAT_MAT3x4, 0x8B68)
WEBGL_CONSTANTS_EACH(FLOAT_MAT4x2, 0x8B69)
WEBGL_CONSTANTS_EACH(FLOAT_MAT4x3, 0x8B6A)
WEBGL_CONSTANTS_EACH(SRGB, 0x8C40)
WEBGL_CONSTANTS_EACH(SRGB8, 0x8C41)
WEBGL_CONSTANTS_EACH(SRGB8_ALPHA8, 0x8C43)
WEBGL_CONSTANTS_EACH(COMPARE_REF_TO_TEXTURE, 0x884E)
WEBGL_CONSTANTS_EACH(RGBA32F, 0x8814)
WEBGL_CONSTANTS_EACH(RGB32F, 0x8815)
WEBGL_CONSTANTS_EACH(RGBA16F, 0x881A)
WEBGL_CONSTANTS_EACH(RGB16F, 0x881B)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_INTEGER, 0x88FD)
WEBGL_CONSTANTS_EACH(MAX_ARRAY_TEXTURE_LAYERS, 0x88FF)
WEBGL_CONSTANTS_EACH(MIN_PROGRAM_TEXEL_OFFSET, 0x8904)
WEBGL_CONSTANTS_EACH(MAX_PROGRAM_TEXEL_OFFSET, 0x8905)
WEBGL_CONSTANTS_EACH(MAX_VARYING_COMPONENTS, 0x8B4B)
WEBGL_CONSTANTS_EACH(TEXTURE_2D_ARRAY, 0x8C1A)
WEBGL_CONSTANTS_EACH(TEXTURE_BINDING_2D_ARRAY, 0x8C1D)
WEBGL_CONSTANTS_EACH(R11F_G11F_B10F, 0x8C3A)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_10F_11F_11F_REV, 0x8C3B)
WEBGL_CONSTANTS_EACH(RGB9_E5, 0x8C3D)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_5_9_9_9_REV, 0x8C3E)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH, 0x8C76)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BUFFER_MODE, 0x8C7F)
WEBGL_CONSTANTS_EACH(MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS, 0x8C80)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_VARYINGS, 0x8C83)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BUFFER_START, 0x8C84)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BUFFER_SIZE, 0x8C85)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN, 0x8C88)
WEBGL_CONSTANTS_EACH(RASTERIZER_DISCARD, 0x8C89)
WEBGL_CONSTANTS_EACH(MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS, 0x8C8A)
WEBGL_CONSTANTS_EACH(MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS, 0x8C8B)
WEBGL_CONSTANTS_EACH(INTERLEAVED_ATTRIBS, 0x8C8C)
WEBGL_CONSTANTS_EACH(SEPARATE_ATTRIBS, 0x8C8D)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BUFFER, 0x8C8E)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BUFFER_BINDING, 0x8C8F)
WEBGL_CONSTANTS_EACH(RGBA32UI, 0x8D70)
WEBGL_CONSTANTS_EACH(RGB32UI, 0x8D71)
WEBGL_CONSTANTS_EACH(RGBA16UI, 0x8D76)
WEBGL_CONSTANTS_EACH(RGB16UI, 0x8D77)
WEBGL_CONSTANTS_EACH(RGBA8UI, 0x8D7C)
WEBGL_CONSTANTS_EACH(RGB8UI, 0x8D7D)
WEBGL_CONSTANTS_EACH(RGBA32I, 0x8D82)
WEBGL_CONSTANTS_EACH(RGB32I, 0x8D83)
WEBGL_CONSTANTS_EACH(RGBA16I, 0x8D88)
WEBGL_CONSTANTS_EACH(RGB16I, 0x8D89)
WEBGL_CONSTANTS_EACH(RGBA8I, 0x8D8E)
WEBGL_CONSTANTS_EACH(RGB8I, 0x8D8F)
WEBGL_CONSTANTS_EACH(RED_INTEGER, 0x8D94)
WEBGL_CONSTANTS_EACH(RGB_INTEGER, 0x8D98)
WEBGL_CONSTANTS_EACH(RGBA_INTEGER, 0x8D99)
WEBGL_CONSTANTS_EACH(SAMPLER_2D_ARRAY, 0x8DC1)
WEBGL_CONSTANTS_EACH(SAMPLER_2D_ARRAY_SHADOW, 0x8DC4)
WEBGL_CONSTANTS_EACH(SAMPLER_CUBE_SHADOW, 0x8DC5)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_VEC2, 0x8DC6)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_VEC3, 0x8DC7)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_VEC4, 0x8DC8)
WEBGL_CONSTANTS_EACH(INT_SAMPLER_2D, 0x8DCA)
WEBGL_CONSTANTS_EACH(INT_SAMPLER_3D, 0x8DCB)
WEBGL_CONSTANTS_EACH(INT_SAMPLER_CUBE, 0x8DCC)
WEBGL_CONSTANTS_EACH(INT_SAMPLER_2D_ARRAY, 0x8DCF)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_SAMPLER_2D, 0x8DD2)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_SAMPLER_3D, 0x8DD3)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_SAMPLER_CUBE, 0x8DD4)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_SAMPLER_2D_ARRAY, 0x8DD7)
WEBGL_CONSTANTS_EACH(DEPTH_COMPONENT32F, 0x8CAC)
WEBGL_CONSTANTS_EACH(DEPTH32F_STENCIL8, 0x8CAD)
WEBGL_CONSTANTS_EACH(FLOAT_32_UNSIGNED_INT_24_8_REV, 0x8DAD)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING, 0x8210)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE, 0x8211)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_RED_SIZE, 0x8212)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_GREEN_SIZE, 0x8213)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_BLUE_SIZE, 0x8214)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE, 0x8215)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE, 0x8216)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, 0x8217)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_DEFAULT, 0x8218)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_UNDEFINED, 0x8219)
WEBGL_CONSTANTS_EACH(UNSIGNED_INT_24_8, 0x84FA)
WEBGL_CONSTANTS_EACH(DEPTH24_STENCIL8, 0x88F0)
WEBGL_CONSTANTS_EACH(UNSIGNED_NORMALIZED, 0x8C17)
WEBGL_CONSTANTS_EACH(DRAW_FRAMEBUFFER_BINDING, 0x8CA6) /* Same as FRAMEBUFFER_BINDING */
WEBGL_CONSTANTS_EACH(READ_FRAMEBUFFER, 0x8CA8)
WEBGL_CONSTANTS_EACH(DRAW_FRAMEBUFFER, 0x8CA9)
WEBGL_CONSTANTS_EACH(READ_FRAMEBUFFER_BINDING, 0x8CAA)
WEBGL_CONSTANTS_EACH(RENDERBUFFER_SAMPLES, 0x8CAB)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER, 0x8CD4)
WEBGL_CONSTANTS_EACH(MAX_COLOR_ATTACHMENTS, 0x8CDF)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT1, 0x8CE1)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT2, 0x8CE2)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT3, 0x8CE3)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT4, 0x8CE4)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT5, 0x8CE5)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT6, 0x8CE6)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT7, 0x8CE7)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT8, 0x8CE8)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT9, 0x8CE9)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT10, 0x8CEA)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT11, 0x8CEB)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT12, 0x8CEC)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT13, 0x8CED)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT14, 0x8CEE)
WEBGL_CONSTANTS_EACH(COLOR_ATTACHMENT15, 0x8CEF)
WEBGL_CONSTANTS_EACH(FRAMEBUFFER_INCOMPLETE_MULTISAMPLE, 0x8D56)
WEBGL_CONSTANTS_EACH(MAX_SAMPLES, 0x8D57)
WEBGL_CONSTANTS_EACH(HALF_FLOAT, 0x140B)
WEBGL_CONSTANTS_EACH(RG, 0x8227)
WEBGL_CONSTANTS_EACH(RG_INTEGER, 0x8228)
WEBGL_CONSTANTS_EACH(R8, 0x8229)
WEBGL_CONSTANTS_EACH(RG8, 0x822B)
WEBGL_CONSTANTS_EACH(R16F, 0x822D)
WEBGL_CONSTANTS_EACH(R32F, 0x822E)
WEBGL_CONSTANTS_EACH(RG16F, 0x822F)
WEBGL_CONSTANTS_EACH(RG32F, 0x8230)
WEBGL_CONSTANTS_EACH(R8I, 0x8231)
WEBGL_CONSTANTS_EACH(R8UI, 0x8232)
WEBGL_CONSTANTS_EACH(R16I, 0x8233)
WEBGL_CONSTANTS_EACH(R16UI, 0x8234)
WEBGL_CONSTANTS_EACH(R32I, 0x8235)
WEBGL_CONSTANTS_EACH(R32UI, 0x8236)
WEBGL_CONSTANTS_EACH(RG8I, 0x8237)
WEBGL_CONSTANTS_EACH(RG8UI, 0x8238)
WEBGL_CONSTANTS_EACH(RG16I, 0x8239)
WEBGL_CONSTANTS_EACH(RG16UI, 0x823A)
WEBGL_CONSTANTS_EACH(RG32I, 0x823B)
WEBGL_CONSTANTS_EACH(RG32UI, 0x823C)
WEBGL_CONSTANTS_EACH(VERTEX_ARRAY_BINDING, 0x85B5)
WEBGL_CONSTANTS_EACH(R8_SNORM, 0x8F94)
WEBGL_CONSTANTS_EACH(RG8_SNORM, 0x8F95)
WEBGL_CONSTANTS_EACH(RGB8_SNORM, 0x8F96)
WEBGL_CONSTANTS_EACH(RGBA8_SNORM, 0x8F97)
WEBGL_CONSTANTS_EACH(SIGNED_NORMALIZED, 0x8F9C)
WEBGL_CONSTANTS_EACH(PRIMITIVE_RESTART_FIXED_INDEX, 0x8D69)
WEBGL_CONSTANTS_EACH(COPY_READ_BUFFER, 0x8F36)
WEBGL_CONSTANTS_EACH(COPY_WRITE_BUFFER, 0x8F37)
WEBGL_CONSTANTS_EACH(COPY_READ_BUFFER_BINDING, 0x8F36) /* Same as COPY_READ_BUFFER */
WEBGL_CONSTANTS_EACH(COPY_WRITE_BUFFER_BINDING, 0x8F37) /* Same as COPY_WRITE_BUFFER */
WEBGL_CONSTANTS_EACH(UNIFORM_BUFFER, 0x8A11)
WEBGL_CONSTANTS_EACH(UNIFORM_BUFFER_BINDING, 0x8A28)
WEBGL_CONSTANTS_EACH(UNIFORM_BUFFER_START, 0x8A29)
WEBGL_CONSTANTS_EACH(UNIFORM_BUFFER_SIZE, 0x8A2A)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_UNIFORM_BLOCKS, 0x8A2B)
WEBGL_CONSTANTS_EACH(MAX_FRAGMENT_UNIFORM_BLOCKS, 0x8A2D)
WEBGL_CONSTANTS_EACH(MAX_COMBINED_UNIFORM_BLOCKS, 0x8A2E)
WEBGL_CONSTANTS_EACH(MAX_UNIFORM_BUFFER_BINDINGS, 0x8A2F)
WEBGL_CONSTANTS_EACH(MAX_UNIFORM_BLOCK_SIZE, 0x8A30)
WEBGL_CONSTANTS_EACH(MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS, 0x8A31)
WEBGL_CONSTANTS_EACH(MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS, 0x8A33)
WEBGL_CONSTANTS_EACH(UNIFORM_BUFFER_OFFSET_ALIGNMENT, 0x8A34)
WEBGL_CONSTANTS_EACH(ACTIVE_UNIFORM_BLOCKS, 0x8A36)
WEBGL_CONSTANTS_EACH(UNIFORM_TYPE, 0x8A37)
WEBGL_CONSTANTS_EACH(UNIFORM_SIZE, 0x8A38)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_INDEX, 0x8A3A)
WEBGL_CONSTANTS_EACH(UNIFORM_OFFSET, 0x8A3B)
WEBGL_CONSTANTS_EACH(UNIFORM_ARRAY_STRIDE, 0x8A3C)
WEBGL_CONSTANTS_EACH(UNIFORM_MATRIX_STRIDE, 0x8A3D)
WEBGL_CONSTANTS_EACH(UNIFORM_IS_ROW_MAJOR, 0x8A3E)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_BINDING, 0x8A3F)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_DATA_SIZE, 0x8A40)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_ACTIVE_UNIFORMS, 0x8A42)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES, 0x8A43)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER, 0x8A44)
WEBGL_CONSTANTS_EACH(UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER, 0x8A46)
WEBGL_CONSTANTS_EACH(INVALID_INDEX, 0xFFFFFFFF)
WEBGL_CONSTANTS_EACH(MAX_VERTEX_OUTPUT_COMPONENTS, 0x9122)
WEBGL_CONSTANTS_EACH(MAX_FRAGMENT_INPUT_COMPONENTS, 0x9125)
WEBGL_CONSTANTS_EACH(MAX_SERVER_WAIT_TIMEOUT, 0x9111)
WEBGL_CONSTANTS_EACH(OBJECT_TYPE, 0x9112)
WEBGL_CONSTANTS_EACH(SYNC_CONDITION, 0x9113)
WEBGL_CONSTANTS_EACH(SYNC_STATUS, 0x9114)
WEBGL_CONSTANTS_EACH(SYNC_FLAGS, 0x9115)
WEBGL_CONSTANTS_EACH(SYNC_FENCE, 0x9116)
WEBGL_CONSTANTS_EACH(SYNC_GPU_COMMANDS_COMPLETE, 0x9117)
WEBGL_CONSTANTS_EACH(UNSIGNALED, 0x9118)
WEBGL_CONSTANTS_EACH(SIGNALED, 0x9119)
WEBGL_CONSTANTS_EACH(ALREADY_SIGNALED, 0x911A)
WEBGL_CONSTANTS_EACH(TIMEOUT_EXPIRED, 0x911B)
WEBGL_CONSTANTS_EACH(CONDITION_SATISFIED, 0x911C)
WEBGL_CONSTANTS_EACH(WAIT_FAILED, 0x911D)
WEBGL_CONSTANTS_EACH(SYNC_FLUSH_COMMANDS_BIT, 0x00000001)
WEBGL_CONSTANTS_EACH(VERTEX_ATTRIB_ARRAY_DIVISOR, 0x88FE)
WEBGL_CONSTANTS_EACH(ANY_SAMPLES_PASSED, 0x8C2F)
WEBGL_CONSTANTS_EACH(ANY_SAMPLES_PASSED_CONSERVATIVE, 0x8D6A)
WEBGL_CONSTANTS_EACH(SAMPLER_BINDING, 0x8919)
WEBGL_CONSTANTS_EACH(RGB10_A2UI, 0x906F)
WEBGL_CONSTANTS_EACH(TEXTURE_SWIZZLE_R, 0x8E42)
WEBGL_CONSTANTS_EACH(TEXTURE_SWIZZLE_G, 0x8E43)
WEBGL_CONSTANTS_EACH(TEXTURE_SWIZZLE_B, 0x8E44)
WEBGL_CONSTANTS_EACH(TEXTURE_SWIZZLE_A, 0x8E45)
WEBGL_CONSTANTS_EACH(GREEN, 0x1904)
WEBGL_CONSTANTS_EACH(BLUE, 0x1905)
WEBGL_CONSTANTS_EACH(INT_2_10_10_10_REV, 0x8D9F)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK, 0x8E22)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_PAUSED, 0x8E23)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_ACTIVE, 0x8E24)
WEBGL_CONSTANTS_EACH(TRANSFORM_FEEDBACK_BINDING, 0x8E25)
WEBGL_CONSTANTS_EACH(COMPRESSED_R11_EAC, 0x9270)
WEBGL_CONSTANTS_EACH(COMPRESSED_SIGNED_R11_EAC, 0x9271)
WEBGL_CONSTANTS_EACH(COMPRESSED_RG11_EAC, 0x9272)
WEBGL_CONSTANTS_EACH(COMPRESSED_SIGNED_RG11_EAC, 0x9273)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGB8_ETC2, 0x9274)
WEBGL_CONSTANTS_EACH(COMPRESSED_SRGB8_ETC2, 0x9275)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2, 0x9276)
WEBGL_CONSTANTS_EACH(COMPRESSED_SRGB8_PUNCHTHROUGH_ALPHA1_ETC2, 0x9277)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGBA8_ETC2_EAC, 0x9278)
WEBGL_CONSTANTS_EACH(COMPRESSED_SRGB8_ALPHA8_ETC2_EAC, 0x9279)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGB_S3TC_DXT1_EXT, 0x83F0)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGBA_S3TC_DXT1_EXT, 0x83F1)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGBA_S3TC_DXT3_EXT, 0x83F2)
WEBGL_CONSTANTS_EACH(COMPRESSED_RGBA_S3TC_DXT5_EXT, 0x83F3)
WEBGL_CONSTANTS_EACH(TEXTURE_IMMUTABLE_FORMAT, 0x912F)
WEBGL_CONSTANTS_EACH(MAX_ELEMENT_INDEX, 0x8D6B)
WEBGL_CONSTANTS_EACH(NUM_SAMPLE_COUNTS, 0x9380)
WEBGL_CONSTANTS_EACH(TEXTURE_IMMUTABLE_LEVELS, 0x82DF)

// Some Plask non-WebGL enums, some of which are likely a bad idea.
#if PLASK_OSX
WEBGL_CONSTANTS_EACH(UNPACK_CLIENT_STORAGE_APPLE, GL_UNPACK_CLIENT_STORAGE_APPLE)
#endif
WEBGL_CONSTANTS_EACH(DEPTH_COMPONENT32, 0x81A7)
WEBGL_CONSTANTS_EACH(MULTISAMPLE, 0x809D)
// Rectangle textures (used by Syphon and AVPlayer, for example).
WEBGL_CONSTANTS_EACH(TEXTURE_RECTANGLE, 0x84F5)
WEBGL_CONSTANTS_EACH(TEXTURE_BINDING_RECTANGLE, 0x84F6)
WEBGL_CONSTANTS_EACH(MAX_RECTANGLE_TEXTURE_SIZE, 0x84F8)
WEBGL_CONSTANTS_EACH(SAMPLER_2D_RECT, 0x8B63)
#endif

// WebGL parameters more or less copied directly from the spec.
// The returned type is mapped to a more specific identifier, ex:
//   Float32Arrayx2 instead of "Float32Array (with 2 elements)"
#ifdef WEBGL_PARAMS_EACH
WEBGL_PARAMS_EACH(ACTIVE_TEXTURE, GLenum)
WEBGL_PARAMS_EACH(ALIASED_LINE_WIDTH_RANGE, Float32Arrayx2)
WEBGL_PARAMS_EACH(ALIASED_POINT_SIZE_RANGE, Float32Arrayx2)
WEBGL_PARAMS_EACH(ALPHA_BITS, GLint)
WEBGL_PARAMS_EACH(ARRAY_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(BLEND, GLboolean)
WEBGL_PARAMS_EACH(BLEND_COLOR, Float32Arrayx4)
WEBGL_PARAMS_EACH(BLEND_DST_ALPHA, GLenum)
WEBGL_PARAMS_EACH(BLEND_DST_RGB, GLenum)
WEBGL_PARAMS_EACH(BLEND_EQUATION_ALPHA, GLenum)
WEBGL_PARAMS_EACH(BLEND_EQUATION_RGB, GLenum)
WEBGL_PARAMS_EACH(BLEND_SRC_ALPHA, GLenum)
WEBGL_PARAMS_EACH(BLEND_SRC_RGB, GLenum)
WEBGL_PARAMS_EACH(BLUE_BITS, GLint)
WEBGL_PARAMS_EACH(COLOR_CLEAR_VALUE, Float32Arrayx4)
WEBGL_PARAMS_EACH(COLOR_WRITEMASK, GLbooleanx4)
WEBGL_PARAMS_EACH(COMPRESSED_TEXTURE_FORMATS, Uint32Array)
WEBGL_PARAMS_EACH(CULL_FACE, GLboolean)
WEBGL_PARAMS_EACH(CULL_FACE_MODE, GLenum)
WEBGL_PARAMS_EACH(CURRENT_PROGRAM, WebGLProgram)
WEBGL_PARAMS_EACH(DEPTH_BITS, GLint)
WEBGL_PARAMS_EACH(DEPTH_CLEAR_VALUE, GLfloat)
WEBGL_PARAMS_EACH(DEPTH_FUNC, GLenum)
WEBGL_PARAMS_EACH(DEPTH_RANGE, Float32Arrayx2)
WEBGL_PARAMS_EACH(DEPTH_TEST, GLboolean)
WEBGL_PARAMS_EACH(DEPTH_WRITEMASK, GLboolean)
WEBGL_PARAMS_EACH(DITHER, GLboolean)
WEBGL_PARAMS_EACH(ELEMENT_ARRAY_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(FRAMEBUFFER_BINDING, WebGLFramebuffer)
WEBGL_PARAMS_EACH(FRONT_FACE, GLenum)
WEBGL_PARAMS_EACH(GENERATE_MIPMAP_HINT, GLenum)
WEBGL_PARAMS_EACH(GREEN_BITS, GLint)
WEBGL_PARAMS_EACH(IMPLEMENTATION_COLOR_READ_FORMAT, GLenum)
WEBGL_PARAMS_EACH(IMPLEMENTATION_COLOR_READ_TYPE, GLenum)
WEBGL_PARAMS_EACH(LINE_WIDTH, GLfloat)
WEBGL_PARAMS_EACH(MAX_COMBINED_TEXTURE_IMAGE_UNITS, GLint)
WEBGL_PARAMS_EACH(MAX_CUBE_MAP_TEXTURE_SIZE, GLint)
WEBGL_PARAMS_EACH(MAX_FRAGMENT_UNIFORM_VECTORS, GLint)
WEBGL_PARAMS_EACH(MAX_RENDERBUFFER_SIZE, GLint)
WEBGL_PARAMS_EACH(MAX_TEXTURE_IMAGE_UNITS, GLint)
WEBGL_PARAMS_EACH(MAX_TEXTURE_SIZE, GLint)
WEBGL_PARAMS_EACH(MAX_VARYING_VECTORS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_ATTRIBS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_TEXTURE_IMAGE_UNITS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_UNIFORM_VECTORS, GLint)
WEBGL_PARAMS_EACH(MAX_VIEWPORT_DIMS, Int32Arrayx2)
WEBGL_PARAMS_EACH(PACK_ALIGNMENT, GLint)
WEBGL_PARAMS_EACH(POLYGON_OFFSET_FACTOR, GLfloat)
WEBGL_PARAMS_EACH(POLYGON_OFFSET_FILL, GLboolean)
WEBGL_PARAMS_EACH(POLYGON_OFFSET_UNITS, GLfloat)
WEBGL_PARAMS_EACH(RED_BITS, GLint)
WEBGL_PARAMS_EACH(RENDERBUFFER_BINDING, WebGLRenderbuffer)
WEBGL_PARAMS_EACH(RENDERER, DOMString)
WEBGL_PARAMS_EACH(SAMPLE_BUFFERS, GLint)
WEBGL_PARAMS_EACH(SAMPLE_COVERAGE_INVERT, GLboolean)
WEBGL_PARAMS_EACH(SAMPLE_COVERAGE_VALUE, GLfloat)
WEBGL_PARAMS_EACH(SAMPLES, GLint)
WEBGL_PARAMS_EACH(SCISSOR_BOX, Int32Arrayx4)
WEBGL_PARAMS_EACH(SCISSOR_TEST, GLboolean)
WEBGL_PARAMS_EACH(SHADING_LANGUAGE_VERSION, DOMString)
WEBGL_PARAMS_EACH(STENCIL_BACK_FAIL, GLenum)
WEBGL_PARAMS_EACH(STENCIL_BACK_FUNC, GLenum)
WEBGL_PARAMS_EACH(STENCIL_BACK_PASS_DEPTH_FAIL, GLenum)
WEBGL_PARAMS_EACH(STENCIL_BACK_PASS_DEPTH_PASS, GLenum)
WEBGL_PARAMS_EACH(STENCIL_BACK_REF, GLint)
WEBGL_PARAMS_EACH(STENCIL_BACK_VALUE_MASK, GLuint)
WEBGL_PARAMS_EACH(STENCIL_BACK_WRITEMASK, GLuint)
WEBGL_PARAMS_EACH(STENCIL_BITS, GLint)
WEBGL_PARAMS_EACH(STENCIL_CLEAR_VALUE, GLint)
WEBGL_PARAMS_EACH(STENCIL_FAIL, GLenum)
WEBGL_PARAMS_EACH(STENCIL_FUNC, GLenum)
WEBGL_PARAMS_EACH(STENCIL_PASS_DEPTH_FAIL, GLenum)
WEBGL_PARAMS_EACH(STENCIL_PASS_DEPTH_PASS, GLenum)
WEBGL_PARAMS_EACH(STENCIL_REF, GLint)
WEBGL_PARAMS_EACH(STENCIL_TEST, GLboolean)
WEBGL_PARAMS_EACH(STENCIL_VALUE_MASK, GLuint)
WEBGL_PARAMS_EACH(STENCIL_WRITEMASK, GLuint)
WEBGL_PARAMS_EACH(SUBPIXEL_BITS, GLint)
WEBGL_PARAMS_EACH(TEXTURE_BINDING_2D, WebGLTexture)
WEBGL_PARAMS_EACH(TEXTURE_BINDING_CUBE_MAP, WebGLTexture)
WEBGL_PARAMS_EACH(UNPACK_ALIGNMENT, GLint)
WEBGL_PARAMS_EACH(UNPACK_COLORSPACE_CONVERSION_WEBGL, GLenum)
WEBGL_PARAMS_EACH(UNPACK_FLIP_Y_WEBGL, GLboolean)
WEBGL_PARAMS_EACH(UNPACK_PREMULTIPLY_ALPHA_WEBGL, GLboolean)
WEBGL_PARAMS_EACH(VENDOR, DOMString)
WEBGL_PARAMS_EACH(VERSION, DOMString)
WEBGL_PARAMS_EACH(VIEWPORT, Int32Arrayx4)

// WebGL 2.0
#if PLASK_WEBGL2
WEBGL_PARAMS_EACH(COPY_READ_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(COPY_WRITE_BUFFER_BINDING, WebGLBuffer)
//WEBGL_PARAMS_EACH(DRAW_BINDING, GLenum)
//WEBGL_PARAMS_EACH(DRAW_FRAMEBUFFER_BINDING, WebGLFramebuffer)
WEBGL_PARAMS_EACH(FRAGMENT_SHADER_DERIVATIVE_HINT, GLenum)
//WEBGL_PARAMS_EACH(IMPLEMENTATION_COLOR_READ_FORMAT, GLenum)
//WEBGL_PARAMS_EACH(IMPLEMENTATION_COLOR_READ_TYPE, GLenum)
WEBGL_PARAMS_EACH(MAX_3D_TEXTURE_SIZE, GLint)
WEBGL_PARAMS_EACH(MAX_ARRAY_TEXTURE_LAYERS, GLint)
WEBGL_PARAMS_EACH(MAX_COLOR_ATTACHMENTS, GLint)
WEBGL_PARAMS_EACH(MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_COMBINED_UNIFORM_BLOCKS, GLint)
WEBGL_PARAMS_EACH(MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_DRAW_BUFFERS, GLint)
WEBGL_PARAMS_EACH(MAX_ELEMENT_INDEX, GLint)
WEBGL_PARAMS_EACH(MAX_ELEMENTS_INDICES, GLint)
WEBGL_PARAMS_EACH(MAX_ELEMENTS_VERTICES, GLint)
WEBGL_PARAMS_EACH(MAX_FRAGMENT_INPUT_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_FRAGMENT_UNIFORM_BLOCKS, GLint)
WEBGL_PARAMS_EACH(MAX_FRAGMENT_UNIFORM_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_PROGRAM_TEXEL_OFFSET, GLint)
WEBGL_PARAMS_EACH(MAX_SAMPLES, GLint)
//WEBGL_PARAMS_EACH(MAX_SERVER_WAIT_TIMEOUT, GLuint64)
WEBGL_PARAMS_EACH(MAX_TEXTURE_LOD_BIAS, GLint)
WEBGL_PARAMS_EACH(MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS, GLint)
WEBGL_PARAMS_EACH(MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_UNIFORM_BLOCK_SIZE, GLint)
WEBGL_PARAMS_EACH(MAX_UNIFORM_BUFFER_BINDINGS, GLint)
WEBGL_PARAMS_EACH(MAX_VARYING_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_OUTPUT_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_UNIFORM_BLOCKS, GLint)
WEBGL_PARAMS_EACH(MAX_VERTEX_UNIFORM_COMPONENTS, GLint)
WEBGL_PARAMS_EACH(MIN_PROGRAM_TEXEL_OFFSET, GLint)
//WEBGL_PARAMS_EACH(PACK_IMAGE_HEIGHT, GLint)
WEBGL_PARAMS_EACH(PACK_ROW_LENGTH, GLint)
//WEBGL_PARAMS_EACH(PACK_SKIP_IMAGES, GLint)
WEBGL_PARAMS_EACH(PACK_SKIP_PIXELS, GLint)
WEBGL_PARAMS_EACH(PACK_SKIP_ROWS, GLint)
WEBGL_PARAMS_EACH(PIXEL_PACK_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(PIXEL_UNPACK_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(PRIMITIVE_RESTART_FIXED_INDEX, GLboolean)
WEBGL_PARAMS_EACH(READ_BUFFER, GLenum)
WEBGL_PARAMS_EACH(READ_FRAMEBUFFER_BINDING, WebGLFramebuffer)
WEBGL_PARAMS_EACH(SAMPLE_ALPHA_TO_COVERAGE, GLboolean)
WEBGL_PARAMS_EACH(SAMPLE_COVERAGE, GLboolean)
//WEBGL_PARAMS_EACH(SAMPLER_BINDING, WebGLSampler)
WEBGL_PARAMS_EACH(TEXTURE_BINDING_2D_ARRAY, WebGLTexture)
WEBGL_PARAMS_EACH(TEXTURE_BINDING_3D, WebGLTexture)
WEBGL_PARAMS_EACH(TRANSFORM_FEEDBACK_ACTIVE, GLboolean)
WEBGL_PARAMS_EACH(TRANSFORM_FEEDBACK_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(TRANSFORM_FEEDBACK_PAUSED, GLboolean)
WEBGL_PARAMS_EACH(TRANSFORM_FEEDBACK_BUFFER_SIZE, GLint)
WEBGL_PARAMS_EACH(TRANSFORM_FEEDBACK_BUFFER_START, GLint)
WEBGL_PARAMS_EACH(UNIFORM_BUFFER_BINDING, WebGLBuffer)
WEBGL_PARAMS_EACH(UNIFORM_BUFFER_OFFSET_ALIGNMENT, GLint)
WEBGL_PARAMS_EACH(UNIFORM_BUFFER_SIZE, GLint)
WEBGL_PARAMS_EACH(UNIFORM_BUFFER_START, GLint)
WEBGL_PARAMS_EACH(UNPACK_IMAGE_HEIGHT, GLint)
WEBGL_PARAMS_EACH(UNPACK_ROW_LENGTH, GLint)
WEBGL_PARAMS_EACH(UNPACK_SKIP_IMAGES, GLboolean)
WEBGL_PARAMS_EACH(UNPACK_SKIP_PIXELS, GLboolean)
WEBGL_PARAMS_EACH(UNPACK_SKIP_ROWS, GLboolean)
WEBGL_PARAMS_EACH(VERTEX_ARRAY_BINDING, WebGLVertexArrayObject)
#endif
#endif
