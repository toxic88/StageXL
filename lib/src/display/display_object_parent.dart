part of stagexl.display;

abstract class DisplayObjectParent extends DisplayObject {

  int get numChildren;

  void addChild(DisplayObject child);
  void addChildAt(DisplayObject child, int index);

  void removeChild(DisplayObject child);
  void removeChildAt(int index);

  DisplayObject getChildAt(int index);
  DisplayObject getChildByName(String name);
  int getChildIndex(DisplayObject child);
}