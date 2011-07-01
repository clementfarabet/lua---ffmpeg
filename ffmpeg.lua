----------------------------------------------------------------------
--
-- Copyright (c) 2011 Clement Farabet, Marco Scoffier
-- 
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
-- 
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- 
----------------------------------------------------------------------
-- description:
--     ffmpeg - provides a Video class that decodes arbitrary video
--              formats using ffmpeg (via system calls) and returns
--              them in tables of torch.Tensor().
--
-- history: 
--     June 30, 2011, 11:22PM - import from our repo - Clement Farabet
----------------------------------------------------------------------

require 'xlua'
require 'sys'
require 'torch'
require 'image'

do
   ffmpeg = {}
   local vid = torch.class('ffmpeg.Video')
   local vid_format = 'frame-%06d.'

   ----------------------------------------------------------------------
   -- __init()
   -- loads arbitrary videos, using FFMPEG (and a temp cache)
   -- returns a table (list) of images
   --
   function vid:__init(...)
      -- usage
      xlua.unpack_class(
         self, {...}, 'Video',
         'loads a video into a table of tensors:\n'
            .. ' + relies on ffpmeg, which must be installed\n'
            .. ' + creates a local scratch/ to hold jpegs',
         {arg='path', type='string', help='path to video'},
         {arg='width', type='number', help='width', default=500},
         {arg='height', type='number', help='height', default=376},
         {arg='fps', type='number', help='frames per second', default=5},
         {arg='length', type='number', help='length, in seconds', default=5},
         {arg='channel', type='number', help='video channel', default=0},
         {arg='load', type='boolean', help='loads frames after conversion', default=true},
         {arg='delete', type='boolean', help='clears (rm) frames after load', default=true},
         {arg='encoding', type='string', help='format of dumped frames', default='png'},
         {arg='tensor', type='torch.Tensor', help='provide a packed tensor (WxHxCxN or WxHxN), that bypasses path'}
      )

      -- check ffmpeg existence
      local res = sys.execute('ffmpeg')
      if res:find('not found') then 
         local c = sys.COLORS
         error(c.Red .. 'ffmpeg required, please install it (apt-get install ffmpeg)' .. c.none)
      end

      -- cleanup path
      self.path = self.path:gsub('^~',os.getenv('HOME'))

      -- is data provided ?
      if self.tensor then
         local outer = self.tensor:nDimension()
         self.nframes = self.tensor:size(outer)
         self[1] = {}
         for i = 1,self.nframes do
            table.insert(self[1], self.tensor:select(outer,i))
         end
         self.path = 'tensor-'..random.random()
         self.width = self.tensor:size(1)
         self.height = self.tensor:size(2)
         self.load = true
         return
      else
         -- auto correct width/height
         local width = math.floor(self.width/2)*2
         local height = math.floor(self.height/2)*2
         if width ~= self.width or height ~= self.height then
            self.width = width
            self.height = height
            print('WARNING: geometry has been changed to accomodate ffmpeg [' 
                  ..width.. 'x' ..height.. ']')
         end
      end

      -- load channel(s)
      local channel = self.channel
      if type(channel) ~= 'table' then channel = {channel} end
      for i = 1,#channel do
         self[i] = {}
         self:loadChannel(channel[i], self[i])
         self[i].channel = channel
      end

      -- cleanup disk
      if self.load and self.path and self.delete then
         self:clear()
      end
   end

   -- make name for disk cache from ffmpeg
   function vid:mktemppath(c)
      local sdirname = sys.basename(self.path) .. '_' .. 
      self.fps .. 'fps_' .. 
      self.width .. 'x' .. self.height .. '_' .. 
      self.length .. 's_c' .. 
      c .. '_' .. self.encoding 

      local path_cache = sys.concat('scratch',sdirname)
      return path_cache
   end

   -- return the string format of dumped files
   function vid:getformat(c)
      if not self[c].path then 
         self[c].path = self:mktemppath(c)
      end
      os.execute('mkdir -p ' .. self[c].path)
      return sys.concat(self[c].path ,vid_format .. 'png')
   end

   ----------------------------------------------------------------------
   -- loadChannel()
   -- loads a channel
   --
   function vid:loadChannel(channel, where)
      where.path = self:mktemppath(channel)
      -- file name format
      where.sformat = vid_format .. self.encoding
      
      -- Only make cache dir and process video, if dir does not exist
      -- or if the source file is newer than the cache.  Could have
      -- flag to force processing.
      local sfile = sys.concat(where.path,string.format(where.sformat,1))
      if not sys.dirp(where.path)
         or not sys.filep(sfile)
         or sys.fstat(self.path) > sys.fstat(sfile)
      then
	 -- make disk cache dir
	 os.execute('mkdir -p ' .. where.path) 
	 -- process video
	 if self.path then 
	    local ffmpeg_cmd = 'ffmpeg -i ' .. self.path .. 
	       ' -r ' .. self.fps .. 
	       ' -t ' .. self.length ..
	       ' -map 0.' .. channel ..
	       ' -s ' .. self.width .. 'x' .. self.height .. 
	       ' -qscale 1' ..
	       ' ' .. sys.concat(where.path, where.sformat) ..
            ' 2> /dev/null'
	    print(ffmpeg_cmd)
	    os.execute(ffmpeg_cmd)
	 end
      end

      print('Using frames in ' .. sys.concat(where.path, where.sformat))

      -- load Images
      local idx = 1
      for file in sys.files(where.path) do
         if file ~= '.' and file ~= '..' then
            local fname = sys.concat(where.path,string.format(where.sformat,idx))
            if not self.load then
               table.insert(where, fname)
            else
               table.insert(where, image.load(fname):narrow(3,1,3))
            end
            idx = idx + 1
         end
      end

      -- update nb of frames
      self.nframes = #where
   end

   
   ----------------------------------------------------------------------
   -- get_frame
   -- as there are two ways to store, you can't index self[1] directly
   function vid:get_frame(c,i)
      if self.load then
	 return self[c][i]
      else 
	 if self.encoding == 'png' then 
	    -- png is loaded in RGBA
	    return image.load(self[c][i]):narrow(3,1,3)
	 else
	    return image.load(self[c][i])
	 end
      end
   end


   ----------------------------------------------------------------------
   -- forward
   -- a simple forward() method, that returns the next frame(s) available
   function vid:forward()
      -- current pointer
      self.current = self.current or 1
      -- nb channels
      local nchannels = #self
      if nchannels == 1 then
         -- get next frame
         self.output = self.output or torch.Tensor()
         local nextframe = self:get_frame(1,self.current)
         self.output:resizeAs(nextframe):copy(nextframe)
      else
         -- get next frames
         self.output = self.output or {}
         for c = 1,nchannels do
            local nextframe = self:get_frame(c,self.current)
            self.output[c] = self.output[c] or torch.Tensor()
            self.output[c]:resizeAs(nextframe):copy(nextframe)
         end
      end
      self.current = self.current + 1
      if self.current > #self[1] then self.current = 1 end
      return self.output
   end


   ----------------------------------------------------------------------
   -- totensor
   -- exports video content to 4D tensor
   function vid:totensor(...)
      local args, channel, offset, nframes = xlua.unpack(
         {...},
         'video:totensor',
         'exports frames to a 4D tensor',
         {arg='channel', type='number', help='channel to export', default=1},
         {arg='offset', type='number', help='offset to start from', default=1},
         {arg='nframes', type='number', help='number of frames to export [default = MAX]'}
      )
      nframes = nframes or self.nframes
      local sequence = self[channel]
      local tensor
      if sequence[1]:nDimension() == 3 then
         tensor = torch.Tensor(sequence[1]:size(1),sequence[1]:size(2),
                               sequence[1]:size(3),nframes)
      else
         tensor = torch.Tensor(sequence[1]:size(1),sequence[1]:size(2),1,nframes)
      end
      for i = 1,nframes do
         tensor:select(4,i):copy(sequence[offset+i-1])
         if (offset+i-1) == self.nframes then break end
      end
      return tensor
   end


   ----------------------------------------------------------------------
   -- dump()
   -- dump all the video frames in path
   -- @param path     folder to save the files
   --
   function vid:dump(path)
      os.execute('mkdir -p ' .. path) 
      -- dump pngs
      print('Dumping Frames into '..path..'...')
      local nchannels = #self
      for c = 1,nchannels do
         -- set the channel path if needed
         self.encoding = 'png'
         format = vid_format .. 'png'
         -- remove if dir exists
         local lpath = path .. '_fps_' ..  
            self.width .. 'x' .. self.height .. '_' .. 
            self.length .. 's_c' .. 
            c-1 .. '_' .. self.encoding 
         if sys.dirp(lpath) then
            os.execute('rm -rf ' .. lpath)
         end
            os.execute('mkdir -p ' .. lpath)
            for i,frame in ipairs(self[c]) do
               xlua.progress(i,#self[c])
               local ofname = sys.concat(lpath, string.format(format, i))
               image.save(ofname,frame)
            end
         end
      end

   ----------------------------------------------------------------------
   -- save()
   -- save the video with all the channels into AVI format
   --
   function vid:save(...)
      -- usage
      local args, outpath, keep = xlua.unpack(
         {...},
         'video:saveVideo',
         'save all the frames into a video file:\n'
            .. ' + video must have been loaded with video:loadVideo()\n'
            .. ' + or else, it must be a list of tensors',
         {arg='outpath', type='string', help='path to save the video', default=''},
         {arg='keep', type='boolean', help='flag to keep the dump images', default=false}
      )
      -- check outpath
      if outpath == '' then
         local c = sys.COLORS
         error(c.Red .. 'You must provide a path to save the video' .. c.none)
      end

      local format = vid_format .. self.encoding
      local nchannels = #self

      -- dump png if content is in ram
      if self.load then
         print('Dumping Frames into Disk...')
         local nchannels = #self
         for c = 1,nchannels do
            -- set the channel path if needed
            local fmt = self.encoding
            self.encoding = 'png'
            self[c].path = self:mktemppath(c-1)
            format = vid_format .. 'png'
            self.encoding = fmt
            -- remove if dir exists
            if sys.dirp(self[c].path) then
               os.execute('rm -rf ' .. self[c].path)
            end
            os.execute('mkdir -p ' .. self[c].path)
            for i,frame in ipairs(self[c]) do
               xlua.progress(i,#self[c])
               local ofname = sys.concat(self[c].path, string.format(format, i))
               image.save(ofname,frame)
            end
         end
      end

      -- warning: -r must come before -i
      local ffmpeg_cmd =  ('ffmpeg -r ' .. self.fps)
      for c = 1,nchannels do
         ffmpeg_cmd = (ffmpeg_cmd ..
                       ' -i ' .. sys.concat(self[c].path, format))
      end
      ffmpeg_cmd = ffmpeg_cmd .. ' -vcodec mjpeg -qscale 1 -an ' .. outpath .. '.avi'
      for c = 2,nchannels do
         ffmpeg_cmd = (ffmpeg_cmd ..
                       '  -vcodec mjpeg -qscale 1 -an  -newvideo')
      end
      ffmpeg_cmd = ffmpeg_cmd .. ' 2> /dev/null'

      -- overwrite the file
      if sys.filep(outpath .. '.avi') then
         print('WARNING: ' .. outpath .. '.avi exist and will be overwritten...')
         os.execute('rm -rf ' .. outpath .. '.avi')
      end

      -- do it
      print(ffmpeg_cmd)
      os.execute(ffmpeg_cmd)

      -- cleanup disk
      if self.load and (not keep) then
         self:clear()
      end
   end


   ----------------------------------------------------------------------
   -- play()
   -- plays a video
   --
   function vid:play(...)
      -- usage
      local args, zoom, loop, fps, channel = xlua.unpack(
         {...},
         'video:playVideo',
         'plays a video:\n'
            .. ' + video must have been loaded with video:loadVideo()\n'
            .. ' + or else, it must be a list of tensors',
         {arg='zoom', type='number', help='zoom', default=1},
         {arg='loop', type='boolean', help='loop', default=false},
         {arg='fps', type='number', help='fps [default = given by seq.fps]'},
         {arg='channel', type='number', help='video channel', default=1}
      )

      -- timer for display
      local timer = qt.QTimer()
      timer.singleShot = false

      -- video index
      local step = false
      local i = 1

      -- qt window plus keyboard handler
      local p =  qtwidget.newwindow(self.width*zoom,self.height*zoom)
      local paused = false
      local keyb = 0
      local ctrl = false
      qt.connect(p.listener,
                 'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
                 function (...) 
                    paused = not paused
                 end)
      qt.connect(p.listener,
                 'sigKeyPress(QString,QByteArray,QByteArray)',
                 function (str, s2)
                    if s2 and s2 == 'Key_Control' then
                       ctrl = true
                    elseif s2 and s2 == 'Key_W' and ctrl then
                       p:close()
                       timer:stop()
                    elseif s2 and s2 == 'Key_L' then
                       keyb = (keyb + 1) % 2
                       if keyb == 1 or sys.OS ~= 'macos' then
                          if loop then
                             print('<Video:play> looping - off')
                             loop = false
                          else
                             print('<Video:play> looping - on')
                             loop = true
                          end
                       end
                    elseif s2 and s2 == 'Key_Space' then
                       keyb = (keyb + 1) % 2
                       if keyb == 1 or sys.OS ~= 'macos' then
                          paused = not paused
                       end
                    elseif s2 and s2 == 'Key_Right' then
                       keyb = (keyb + 1) % 2
                       if keyb == 1 or sys.OS ~= 'macos' then
                          paused = true
                          i = i + 1
                          step = true
                       end
                    elseif s2 and s2 == 'Key_Left' then
                       keyb = (keyb + 1) % 2
                       if keyb == 1 or sys.OS ~= 'macos' then
                          paused = true
                          i = i - 1
                          step = true
                       end
                    else
                       ctrl = false
                    end
                 end)

      -- plays vid
      local disp = Displayer()
      local frame = torch.Tensor()
      local pause = 1 / (fps or self.fps)

      -- disp frame function
      local function dispFrame(i)
         local frame = self[channel][i]
         if not self.load then frame = image.load(frame):narrow(3,1,3) end
         disp:show{tensor=frame,painter=p,legend='playing sequence',zoom=zoom}
         collectgarbage()
      end

      -- timer handler
      timer.interval = pause*1e3
      qt.connect(timer,
                 'timeout()',
                 function()
                    if not paused then
                       dispFrame(i)
                       if i < #self[channel] then
                          i = i + 1
                       elseif loop then
                          i = 1
                       else
                          i = 1
                          paused = true
                       end
                    elseif step then
                       step = false
                       if i > #self[channel] then
                          if loop then
                             i = 1
                          else
                             i = #self[channel]
                          end
                       elseif i < 1 then
                          if loop then
                             i = #self[channel]
                          else
                             i = 1
                          end
                       end
                       dispFrame(i)
                    end
                 end)
      timer:start()

      -- Msg
      print('<Video:play> started - [space] to pause/resume/restart, [L] to loop, [right,left] to step')
   end


   ----------------------------------------------------------------------
   -- this is like __tostring(), to be used for GUIs
   --
   function vid:__show() 
      self:play{}
   end


   ----------------------------------------------------------------------
   -- play3D()
   -- plays a 3D video
   --
   function vid:play3D(...)
      -- usage
      local _, zoom, loop, fps = xlua.unpack(
         {...},
         'video:playVideo3D',
         'plays a video:\n'
            .. ' + video must have been loaded with video:loadVideo()\n'
            .. ' + or else, it must be a list of pairs of tensors',
         {arg='zoom', type='number', help='zoom', default=1},
         {arg='loop', type='boolean', help='loop', default=false},
         {arg='fps', type='number', help='fps [default = given by seq.fps]'}
      )

      -- timer for display
      local timer = qt.QTimer()
      timer.singleShot = false

      -- qt window plus keyboard handler
      local p =  qtwidget.newwindow(self.width*zoom,self.height*zoom)
      local paused = false
      local keyb = 0
      local ctrl = false
      qt.connect(p.listener,
                 'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
                 function (...) 
                    paused = not paused
                 end)
      qt.connect(p.listener,
                 'sigKeyPress(QString,QByteArray,QByteArray)',
                 function (str, s2)
                    if s2 and s2 == 'Key_Control' then
                       ctrl = true
                    elseif s2 and s2 == 'Key_W' and ctrl then
                       p:close()
                       timer:stop()
                    elseif s2 and s2 == 'Key_Space' then
                       keyb = (keyb + 1) % 2
                       if keyb == 1 then
                          paused = not paused
                       end
                    else
                       ctrl = false
                    end
                 end)

      -- plays vid
      local disp = Displayer()
      local frame = torch.Tensor()
      local pause = 1 / (fps or self.fps)

      -- disp frame function
      local function dispFrame(i)
         -- left/right
         local framel = self[1][i]
         local framer = self[2][i]
         -- optional load
         if not self.load then 
            framel = image.load(framel):narrow(3,1,3)
            framer = image.load(framer):narrow(3,1,3)
         end
         -- merged
         frame:resize(framel:size(1),framel:size(2),3)
         frame:select(3,1):copy(framel:select(3,1))
         frame:select(3,2):copy(framer:select(3,1))
         frame:select(3,3):copy(framer:select(3,1))
         -- disp
         disp:show{tensor=frame,
                   painter=p,
                   legend='playing 3D sequence [left=RED, right=CYAN]',
                   zoom=zoom}
         -- clean
         collectgarbage()
      end

      -- Loop Process
      timer.interval = pause*1e3
      local i = 1
      qt.connect(timer,
                 'timeout()',
                 function()
                    if not paused then
                       dispFrame(i)
                       if i < #self[1] then
                          i = i + 1
                       elseif loop then
                          i = 1
                       else
                          i = 1
                          paused = true
                       end
                    end
                 end)
      timer:start()

      -- Msg
      print('<Video:play3D> started - press space to pause/resume/restart')
   end


   ----------------------------------------------------------------------
   -- clear()
   --
   function vid:clear()
      for i = 1,#self do
         local clear = 'rm -rf ' .. self[i].path
         print('clearing video')
         os.execute(clear)
         print(clear)
      end
   end


   ----------------------------------------------------------------------
   -- playYouTube3D() 
   -- plays a video in a format which is acceptable for YouTube 3D (loads jpgs from disk as prepared by Video2imgs)
   --
   function vid:playYouTube3D(...)
      -- usage
      local _, zoom, savefname = xlua.unpack(
         {...},
         'video:playYouTube3D',
         'plays a video:\n'
            .. ' + video must have been loaded with video:loadVideo()\n'
            .. ' + or else, it must be a list of pairs of tensors',
         {arg='zoom', type='number', help='zoom', default=1},
         {arg='savefname', type='string', help='filename in which output movie will be saved'}
      )

      -- enforce 16:9 ratio
      local h  = self.height
      local w  = (h * 16 / 9)
      local w2 = w/2
      local frame = torch.Tensor(w,h,3)
      print('Frame [' .. frame:size(1) .. ', ' .. frame:size(2) .. ', ' .. frame:size(3) .. ']')

      -- create output
      local outp = Video{width=w, height=h, fps=self.fps, 
                         length=self.length, encoding='png'}

      -- plays vid
      zoom = zoom or 1
      local p =	 qtwidget.newwindow(w*zoom,h*zoom)
      local disp = Displayer()
      local pause = 1 / (self.fps or 5) - 0.08
      local idx = 1
      for i = 1,#self[1] do
         -- left/right
         local frameL = self[1][i]
         local frameR = self[2][i]
         -- optional load
         if not self.load then 
            frameL = image.load(frameL):narrow(3,1,3)
            frameR = image.load(frameR):narrow(3,1,3)
         end
	 print('FrameL [' .. frameL:size(1) .. ', ' .. frameL:size(2) .. ', ' .. frameL:size(3) .. ']')
	 
         -- left
         if not (frameL:size(1) == w2 and frameL:size(2) == h) then
            image.scale(frameL,frame:narrow(1,1,w2),'bilinear')
         else
            frame:narrow(1,1,w2):copy(frameL)
         end
         -- right
         if not (frameR:size(1) == w2 and frameR:size(2) == h) then
            image.scale(frameR,frame:narrow(1,w2,w2),'bilinear')
         else 
            frame:narrow(1,w2,w2):copy(frameR)
         end
         frameL = nil 
         frameR = nil
         collectgarbage() -- force GC ...
         -- disp
         disp:show{tensor=frame,painter=p,legend='playing 3D sequence',zoom=zoom}
         if savefname then
            local ofname = sys.concat(outp[1].path, string.format(outp[1].sformat, idx))
            table.insert(outp[1], ofname)
            image.save(ofname,frame)
         end
         idx = idx + 1
         -- need pause to take the image loading time into account.
         if pause and pause>0 then libxlearn.usleep(pause*1e6) end
      end

      -- convert pngs to AVI
      if savefname then
         outp:save(savefname)
      end
   end
end

return ffmpeg