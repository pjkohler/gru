% readext.m
%
%      usage: readext.m()
%         by: justin gardner/modified to read ext. file 
%       date: 05/10/03
%    purpose: Read Ext. file generated by Labview data
%

function d = readext(filename,numchannels)

if (nargin == 1)
  numchannels = -1;
elseif (nargin ~= 2)
  disp('USAGE: readext filename');
  return
end

% check which platform we are running (Unix, Intel Mac, Power Mac)
% MAC, MACI, PCWIN, GLNX86
[platform maxsize endian] = computer;

% set filename
d.filename = filename;
d.channels = [];

% open the file
fid = fopen(filename,'r');
if (fid == -1)
  disp(sprintf('ERROR: Could not open %s',filename));
  return
end

% read the data
%[raw, n] = fread(fid,inf,'unsigned short');
%[raw, n] = fread(fid,inf,'ushort');
if strcmp(endian, 'L')
    [raw, n] = fread(fid,inf,'ushort','ieee-be');
else
    [raw, n] = fread(fid,inf,'ushort');
end

% get the number of channels as the top four bits
topfourbits = bitshift(bitand(raw(1),hex2dec('F000')),-12);
if (topfourbits == 0),d.version = 1;,else,d.version = 2;,end
% if the user hasn't called for a specific number of channelsn
if (numchannels == -1)
  % if there is nothing in the top four bits, then assume 5 channels
  if (topfourbits == 0)
    numchannels = 5;
  else
    numchannels = topfourbits;
  end
else
  if (numchannels ~= topfourbits)
    disp(sprintf('UHOH: Number of channels in file is %i, not %i',topfourbits,numchannels));
  end
end
d.numchannels = numchannels;

% reshape into channels array
d.channels = reshape(raw,numchannels, n/numchannels);  
% remove top 4 bits of each short.
d.channels = bitand(uint16(d.channels),hex2dec('FFF'));
% for each value greater than 0x7FF replace with -0xFFF+value
d.channels = double(d.channels>hex2dec('7FF')).*-double(hex2dec('FFF'))+double(d.channels);
%scale by 5/0x7FF
d.channels = 5*d.channels/double(hex2dec('7ff'));


fclose(fid);

