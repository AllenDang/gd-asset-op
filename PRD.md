# Godot Asset OP (operator)

A godot gdextension, which provide various operators for assets:

1. convert asset to proper format
   1.1 convert image to ktx2
   1.2 convert various audio format to mp3
   1.3 convert texture inside glb to ktx2
   1.4 balance audio volume to specified value

2. probe metainfo from asset
   2.1 probe face_count/aabb/skeleton/animation info from glb
   2.2 probe texture size of ktx2
   2.3 probe audio_length/volume from audio
