library stagexl.filters.displacement_map;

import 'dart:html' show ImageData;
import 'dart:typed_data';

import '../display.dart';
import '../engine.dart';
import '../geom.dart';
import '../internal/tools.dart';

class DisplacementMapFilter extends BitmapFilter {

  final BitmapData bitmapData;
  final Matrix matrix;
  final num scaleX;
  final num scaleY;

  DisplacementMapFilter(BitmapData bitmapData, [
    Matrix matrix = null, num scaleX = 16.0, num scaleY = 16.0]) :

    bitmapData = bitmapData,
    matrix = (matrix != null) ? matrix : new Matrix.fromIdentity(),
    scaleX = scaleX,
    scaleY = scaleY;

  //-----------------------------------------------------------------------------------------------

  BitmapFilter clone() => new DisplacementMapFilter(bitmapData, matrix.clone(), scaleX, scaleY);

  Rectangle<int> get overlap {
    int x = (0.5 * scaleX).abs().ceil();
    int y = (0.5 * scaleY).abs().ceil();
    return new Rectangle<int>(-x, -y, x + x, y + y);
  }

  //-----------------------------------------------------------------------------------------------

  void apply(BitmapData bitmapData, [Rectangle<int> rectangle]) {

    RenderTextureQuad renderTextureQuad = rectangle == null
        ? bitmapData.renderTextureQuad
        : bitmapData.renderTextureQuad.cut(rectangle);

    ImageData mapImageData = this.bitmapData.renderTextureQuad.getImageData();
    ImageData srcImageData = renderTextureQuad.getImageData();
    ImageData dstImageData = renderTextureQuad.createImageData();
    int mapWidth = ensureInt(mapImageData.width);
    int mapHeight = ensureInt(mapImageData.height);
    int srcWidth = ensureInt(srcImageData.width);
    int srcHeight = ensureInt(srcImageData.height);
    int dstWidth = ensureInt(dstImageData.width);
    int dstHeight = ensureInt(dstImageData.height);

    var mapData = mapImageData.data;
    var srcData = srcImageData.data;
    var dstData = dstImageData.data;

    Float32List pqList = renderTextureQuad.pqList;
    num pixelRatio = renderTextureQuad.pixelRatio;
    num scaleX = pixelRatio * this.scaleX;
    num scaleY = pixelRatio * this.scaleX;
    int channelX = BitmapDataChannel.getCanvasIndex(BitmapDataChannel.RED);
    int channelY = BitmapDataChannel.getCanvasIndex(BitmapDataChannel.GREEN);

    // dstPixel[x, y] = srcPixel[
    //     x + ((colorR(x, y) - 128) * scaleX) / 256,
    //     y + ((colorG(x, y) - 128) * scaleY) / 256)];

    Matrix matrix = this.matrix.cloneInvert();
    matrix.prependTranslation(pqList[0], pqList[1]);

    for(int dstY = 0; dstY < dstHeight; dstY++) {
      num mx = dstY * matrix.c + matrix.tx;
      num my = dstY * matrix.d + matrix.ty;
      for(int dstX = 0; dstX < dstWidth; dstX++, mx += matrix.a, my += matrix.b) {
        int mapX = mx.round();
        int mapY = my.round();
        if (mapX < 0) mapX = 0;
        if (mapY < 0) mapY = 0;
        if (mapX >= mapWidth) mapX = mapWidth - 1;
        if (mapY >= mapHeight) mapY = mapHeight - 1;
        int mapOffset = (mapX + mapY * mapWidth) << 2;
        int srcX = dstX + ((mapData[mapOffset + channelX] - 127) * scaleX) ~/ 256;
        int srcY = dstY + ((mapData[mapOffset + channelY] - 127) * scaleY) ~/ 256;
        if (srcX >= 0 && srcY >= 0 && srcX < srcWidth && srcY < srcHeight) {
          int srcOffset = (srcX + srcY * srcWidth) << 2;
          int dstOffset = (dstX + dstY * dstWidth) << 2;
          if (srcOffset > srcData.length - 4) continue;
          if (dstOffset > dstData.length - 4) continue;
          dstData[dstOffset + 0] = srcData[srcOffset + 0];
          dstData[dstOffset + 1] = srcData[srcOffset + 1];
          dstData[dstOffset + 2] = srcData[srcOffset + 2];
          dstData[dstOffset + 3] = srcData[srcOffset + 3];
        }
      }
    }

    renderTextureQuad.putImageData(dstImageData);
  }

  //-----------------------------------------------------------------------------------------------

  void renderFilter(RenderState renderState, RenderTextureQuad renderTextureQuad, int pass) {

    RenderContextWebGL renderContext = renderState.renderContext;
    RenderTexture renderTexture = renderTextureQuad.renderTexture;

    DisplacementMapFilterProgram renderProgram = renderContext.getRenderProgram(
        r"$DisplacementMapFilterProgram", () => new DisplacementMapFilterProgram());

    renderContext.activateRenderProgram(renderProgram);
    renderContext.activateRenderTextureAt(renderTexture, 0);
    renderContext.activateRenderTextureAt(bitmapData.renderTexture, 1);
    renderProgram.configure(this, renderTextureQuad);
    renderProgram.renderQuad(renderState, renderTextureQuad);
  }
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class DisplacementMapFilterProgram extends BitmapFilterProgram {

  String get fragmentShaderSource => """
      precision mediump float;
      uniform sampler2D uTexSampler;
      uniform sampler2D uMapSampler;
      uniform mat3 uMapMatrix;
      uniform mat3 uDisMatrix;
      varying vec2 vTextCoord;
      varying float vAlpha;
      void main() {
        vec3 mapCoord = vec3(vTextCoord.xy, 1) * uMapMatrix;
        vec4 mapColor = texture2D(uMapSampler, mapCoord.xy);
        vec3 displacement = vec3(mapColor.rg - 0.5, 1) * uDisMatrix;
        gl_FragColor = texture2D(uTexSampler, vTextCoord + displacement.xy) * vAlpha;
      }
      """;

  void configure(DisplacementMapFilter displacementMapFilter, RenderTextureQuad renderTextureQuad) {

    var mapMatrix = new Matrix.fromIdentity();
    mapMatrix.copyFromAndConcat(displacementMapFilter.matrix, renderTextureQuad.samplerMatrix);
    mapMatrix.invertAndConcat(displacementMapFilter.bitmapData.renderTextureQuad.samplerMatrix);

    var disMatrix = new Matrix.fromIdentity();
    disMatrix.copyFrom(renderTextureQuad.samplerMatrix);
    disMatrix.scale(displacementMapFilter.scaleX, displacementMapFilter.scaleY);

    var uMapMatrix = new Float32List.fromList([
      mapMatrix.a, mapMatrix.c, mapMatrix.tx,
      mapMatrix.b, mapMatrix.d, mapMatrix.ty,
      0.0, 0.0, 1.0]);

    var uDisMatrix = new Float32List.fromList([
      disMatrix.a, disMatrix.c, 0.0,
      disMatrix.b, disMatrix.d, 0.0,
      0.0, 0.0, 1.0]);

    renderingContext.uniform1i(uniforms["uTexSampler"], 0);
    renderingContext.uniform1i(uniforms["uMapSampler"], 1);
    renderingContext.uniformMatrix3fv(uniforms["uMapMatrix"], false, uMapMatrix);
    renderingContext.uniformMatrix3fv(uniforms["uDisMatrix"], false, uDisMatrix);
  }
}
