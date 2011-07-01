
INSTALL:
$ luarocks --from=http://data.neuflow.org/lua/rocks install ffmpeg

USE:
$ lua
> require 'ffmpeg'
> ffmpeg.Video()
-- prints help

NOTES:
the package depends on external packages: 'xlua', 'sys', 'image' and 'torch'.
the first 3 are automatically installed by Luarocks, but Torch5 needs
to be installed manually.
Also, ffmpeg needs to be in the path at runtime.
