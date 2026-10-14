# Screenshot Shelf

A small native macOS screenshot widget. Rust handles screenshot storage and lifetime. AppKit provides the interface and native drag-and-drop.

The widget appears after a new screenshot. Drag the image to use it, press the green check to keep it, or press × to delete it. A completed drop deletes the source immediately. After 10 minutes without widget action, all pending images are deleted and the widget closes. There is no recovery copy.

Implementation is being delivered in small pull requests.
