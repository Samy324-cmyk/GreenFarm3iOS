#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 imageSize;
uniform float effect;
uniform float linearFilter;
uniform vec4 fxColor;
uniform float alphaPlane;
uniform float blendEnabled;
uniform sampler2D rgbImage;
uniform sampler2D alphaImage;
out vec4 fragColor;

// Both images are opaque, preserving source RGB even when source alpha is zero.
vec4 samplePixel(vec2 pixel) {
  vec2 uv = (clamp(pixel, vec2(0.0), imageSize - vec2(1.0)) + vec2(0.5)) / imageSize;
  return vec4(texture(rgbImage, uv).rgb, texture(alphaImage, uv).r);
}

void main() {
  vec2 xy = FlutterFragCoord().xy;
  vec4 color;
  if (linearFilter > 0.5) {
    vec2 topLeft = floor(xy - vec2(0.5));
    vec2 f = fract(xy - vec2(0.5));
    color = mix(mix(samplePixel(topLeft), samplePixel(topLeft + vec2(1.0, 0.0)), f.x),
                mix(samplePixel(topLeft + vec2(0.0, 1.0)), samplePixel(topLeft + vec2(1.0, 1.0)), f.x), f.y);
  } else {
    color = samplePixel(floor(xy));
  }
  if (effect > 3.5) {
    color.rgb = mix(color.rgb, fxColor.rgb, fxColor.a);
  } else {
    if (effect > 0.5 && effect < 1.5) color.rgb = fxColor.rgb;
    else if (effect > 1.5 && effect < 2.5) color.rgb = vec3(dot(color.rgb, vec3(0.2125, 0.7154, 0.0721)));
    color.a *= fxColor.a;
  }
  if (alphaPlane > 0.5) color.rgb = vec3(color.a);
  if (blendEnabled > 0.5) fragColor = vec4(color.rgb * color.a, color.a);
  else fragColor = vec4(color.rgb, 1.0);
}
