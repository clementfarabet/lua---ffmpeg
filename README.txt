
DEPENDENCIES:
libffmpeg and torch7 (www.torch.ch)

INSTALL:
$ torch-pkg install ffmpeg

USE:
$ torch
> require 'ffmpeg'
> ffmpeg.Video()
-- prints help
> vid = ffmpeg.Video('path/to/some/video.mpg')
> vid:play{}
