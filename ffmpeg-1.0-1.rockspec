
package = "ffmpeg"
version = "1.0-1"

source = {
   url = "ffmpeg-1.0-1.tgz"
}

description = {
   summary = "Provides a Video class, interfacing ffmpeg",
   detailed = [[
         Decodes video frames via ffmpeg, and uses the
         torch.Tensor class to store them.
         Also uses the qt package to display the videos.
   ]],
   homepage = "",
   license = "MIT/X11" -- or whatever you like
}

dependencies = {
   "lua >= 5.1",
   "xlua",
   "sys",
   "torch",
   "image",
}

build = {
   type = "builtin",

   modules = {
      sys = "ffmpeg.lua",
   }
}
