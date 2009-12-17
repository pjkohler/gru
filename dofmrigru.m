% dofmrigru1.m
%
%        $Id:$ 
%      usage: dofmrigru
%         by: justin gardner
%       date: 07/06/09
%    purpose: do initial processing stream from fid files collected on the Varian magnet
%             to MLR nifti file format. You will run this program twice to
%             process this data. The first time files will get moved into
%             your local computer. You then have to manually generate a
%             mask and run peak. Then you run it a second time to do the
%             sense reconstruction and run physiofix, etc. After the second
%             pass you will be ready to run mrInit.
%
%
%             To use this, first make a directory where you want
%             all the data saved on your local machine. Use the same directory name
%             as the one on /usr1 or /usr4 which contains the raw data. For example:
%
%             cd ~/data
%             mkdir S00120091216
%             cd S00120091216
%
%             Now, make sure that your raw data is setup as follows:
%
%             /usr1/yuko/data/S00120091216 should contain all of your data. Including
%             all of the .fid directories)
%             all of the car/ext files
%             all of the stimfiles (if you have them)
%             any pdf files (documents if you have them)
% 
%             Now you can run dofmrigru as follows:
%
%             dofmrigru('fiddir=/usr1/yuko/data')
%
%             Other options:
%                'epirri=eprri5': set which epirri processing function to use
%                'postproc=pp': set which postproc program to use
%                'sense=sense_mac_intel': set which sense reconstruction to use
%
%             First pass will sort through the specified fiddir and copy
%             all of these files in the correct directories on your local
%             computer. All of the initial  
%
function retval = dofmrigru_yukoedits(varargin)

% check arguments
if ~any(nargin == [0 1 2 3 4 5 6 7 8])
  help dofmrigru1
  return
end

% Default arguments
global fiddir;
global epirri;
global postproc;
global sense;
getArgs(varargin,{'fiddir=/usr1/yuko/data','epirri=epirri5','postproc=pp','sense=/usr1/mauro/SenseProj/command_line/current/executables/sense_mac_intel'});

% see if this is the first preprocessing or the second one
if ~isdir('Pre')
  disp(sprintf('Running Initial dofmrigru process'));
  dofmrigru1
else
  disp(sprintf('Running Second dofmrigru process'));
  dofmrigru2
end

%%%%%%%%%%%%%%%%%%%%
%%   dofmrigru2   %%
%%%%%%%%%%%%%%%%%%%%
function dofmrigru2

% get fid file list
fiddir = 'Pre';
fidList = getFileList(fiddir,'fid');
fidList = getFidInfo(fidList);
fidList = sortFidList(fidList);

% look for mask in nifti form
%the mask is made manually before dofmrigru1 from noise/ref in maskdir.
%copy the correct maskfile into Pre MANUALLY
maskList = getFileList(fiddir,'hdr','img','mask'); 
noiseList = getFileList(fiddir,'edt','epr','noise');
refList = getFileList(fiddir,'edt','epr','ref');
% get list of epi scans
epiNums = getEpiScanNums(fidList);
senseScanNums = getSenseScanNums(fidList,epiNums);

% get anatomy scan nums
anatNums = getAnatScanNums(fidList);

% check to make sure that all epi runs are processed
epiNumsWithPeaks = checkForPeaks(fidList,epiNums);

% get which mask goes for each sense file
[maskNums noiseNums refNums] = chooseMaskForSenseFiles(fidList,maskList,noiseList,refList,epiNums);

% check for something to do
if isempty(epiNumsWithPeaks)
  disp(sprintf('(dofmrigru) No epi scans to process'));
  return
end

% check to see if we should quit given that some of the peak files are missing
if length(epiNumsWithPeaks) ~= length(epiNums)
  if ~askuser('You are missing some peak files. Do you still want to continue'),return,end
end

dispList(fidList,epiNumsWithPeaks,sprintf('Epi scans to process'));
dispList(fidList,anatNums,sprintf('Anatomy files'));

% display the commands for processing
processFiles(1,fidList,maskList,noiseList,refList,epiNumsWithPeaks,senseScanNums,anatNums,maskNums,noiseNums,refNums);

% now ask the user if they want to continue, because now we'll actually copy the files and set everything up.
if ~askuser('OK to run above commands?'),return,end

% now do it
processFiles(0,fidList,maskList,noiseList,refList,epiNumsWithPeaks,senseScanNums,anatNums,maskNums,noiseNums,refNums);

%%%%%%%%%%%%%%%%%%%%%%
%%   processFiles   %%
%%%%%%%%%%%%%%%%%%%%%%
function processFiles(justDisplay,fidList,maskList,noiseList,refList,epiNumsWithPeaks,senseScanNums,anatNums,maskNums,noiseNums,refNums)

global postproc;
global sense;

disp(sprintf('=============================================='));
disp(sprintf('Making directories'));
disp(sprintf('=============================================='));

% list of directories to make
dirList = {'Anatomy','Raw','Raw/Tseries','Anal'};

% make them
for i = 1:length(dirList)
  if ~isdir(dirList{i})
    command = sprintf('mkdir(''%s'');',dirList{i});
    if justDisplay,disp(command),else,eval(command),end
  end
end

command = sprintf('cd Pre');
if justDisplay,disp(command),else,eval(command),end

% convert anatomy files into nifti
for i = 1:length(anatNums)
  disp(sprintf('=============================================='));
  disp(sprintf('Copy processed anatomy into Anatomy directory'));
  disp(sprintf('=============================================='));
  command = sprintf('copyfile %s ../Anatomy',setext(fixBadChars(stripext(fidList{anatNums(i)}.filename),{'.','_'}),'hdr'));
  if justDisplay,disp(command),else,eval(command),end
  command = sprintf('copyfile %s ../Anatomy',setext(fixBadChars(stripext(fidList{anatNums(i)}.filename),{'.','_'}),'img'));
  if justDisplay,disp(command),else,eval(command),end
end

for i = 1:length(maskNums)
  disp(sprintf('=============================================='));
  disp(sprintf('Convert masks from nifti to sdt/spr'));
  disp(sprintf('=============================================='));
  % convert mask from nifti to to sdt/spr form
  maskNum = maskNums(find(i==senseScanNums));
  maskname = maskList{maskNum}.filename; % still in nifti form
  command = sprintf('[d h] = cbiReadNifti(''%s'');',maskname);
  if justDisplay,disp(command),else,eval(command),end
  command = sprintf('writesdt(''%s'',d);',setext(maskname,'sdt'));
  if justDisplay,disp(command),else,eval(command),end
end

disp(sprintf('=============================================='));
disp(sprintf('Physiofix, sense process and convert to nifti epi files'));
disp(sprintf('=============================================='));
% physiofix the files
for i = 1:length(epiNumsWithPeaks)
  % see if it is sense
  if any(i==senseScanNums)
    % get some names for things
    fidname = fidList{epiNumsWithPeaks(i)}.filename;
    edtname = setext(fidList{epiNumsWithPeaks(i)}.filename,'edt');
    sdtname = setext(fidList{epiNumsWithPeaks(i)}.filename,'sdt');
    hdrname = setext(fidList{epiNumsWithPeaks(i)}.filename,'hdr');
    noiseNum = noiseNums(find(i==senseScanNums));
    refNum = refNums(find(i==senseScanNums));
    %covarNum = covarNums(find(i==senseScanNums));
    maskname = setext(maskList{maskNum}.filename,'sdt');
    %covarname = covarList{covarNum}.filename;
    noisename = noiseList{noiseNum}.filename;
    refname = refList{refNum}.filename;
    % convert to epis to edt file, doing physiofix and dc correction
    command = sprintf('system(''%s -outtype 1 -dc -physiofix %s %s'')',postproc,fidname,edtname);
    if justDisplay,disp(command),else,eval(command),end
    % run the sense processing for this file
    command = sprintf('system(''%s -data %s -full %s -noise %s -mask %s -remove -recon %s_%s'')',sense,stripext(fidname),stripext(refname),stripext(noisename),stripext(maskname),stripext(fidname),stripext(maskname));
    % command = sprintf('system(''%s -? -? %s %s
    % %s'')',sense,maskname,covarname,edtname); this is for super old sense!
    if justDisplay,disp(command),else,eval(command),end
    % then convert the sdt file into a nifti
    command = sprintf('[trashdata hdr] = fid2nifti(''%s'');',fidname);
    if justDisplay,disp(command),else,eval(command),end
    command = sprintf('data = readsdt(''%s_%s.sdt'');',stripext(sdtname),stripext(maskname));
    if justDisplay,disp(command),else,eval(command),end
    command = sprintf('cbiWriteNifti(''%s_%s.hdr'',data.data,hdr);',stripext(fullfile('..','Raw','TSeries',hdrname)),stripext(maskname));
    if justDisplay,disp(command),else,eval(command),end
  else
    disp(sprintf('UHOH!!!!! plain processing (not sense is not implemented yet!!! FIX FIX FIX!!!)'));
  end
end

command = sprintf('cd ..');
if justDisplay,disp(command),else,eval(command),end

disp(sprintf('=============================================='));
disp(sprintf('DONE'));
disp(sprintf('=============================================='));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   chooseMaskForSenseFiles   %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [maskNums noiseNums refNums] = chooseMaskForSenseFiles(fidList,maskList,noiseList,refList,epiNums)
% set up variables
maskNums = []; noiseNums = []; refNums = [];
if isempty(epiNums),return,end

% get the names of the mask files
for i = 1:length(maskList)
  maskNames{i} = maskList{i}.filename;
end

% get the names of the noise files
for i = 1:length(noiseList)
  noiseNames{i} = noiseList{i}.filename;
end

% get the names of the covar files
for i = 1:length(refList)
  refNames{i} = refList{i}.filename;
end

% get the names of the covar files
%for i = 1:length(covarList)
%  covarNames{i} = covarList{i}.filename;
%end

% get info from scans
for i = 1:length(epiNums)
  scanNames{i} = stripext(fidList{epiNums(i)}.filename);
  maskNamesMatch{i} = maskNames;
  noiseNamesMatch{i} = noiseNames;
  refNamesMatch{i} = refNames;
  % covarNamesMatch{i} = covarNames;
  startTime{i} = fidList{epiNums(i)}.startTimeStr;
  endTime{i} = fidList{epiNums(i)}.endTimeStr;
end

% make an mrParamsDialog where you can select
paramsInfo{1} = {'scanNum',1,'round=1','incdec=[-1 1]',sprintf('minmax=[1 %i]',length(epiNums))};
paramsInfo{2} = {'scanName',scanNames,'group=scanNum','type=String','editable=0'};
paramsInfo{3} = {'startTime',startTime,'group=scanNum','type=String','editable=0'};
paramsInfo{4} = {'endTime',endTime,'group=scanNum','type=String','editable=0'};
paramsInfo{5} = {'maskFile',maskNamesMatch,'group=scanNum'};
% paramsInfo{6} = {'covarFile',covarNamesMatch,'group=scanNum'};
paramsInfo{6} = {'noiseFile',noiseNamesMatch,'group=scanNum'};
paramsInfo{7} = {'refFile',refNamesMatch,'group=scanNum'};

% put out the dialog
if (length(maskNames) == 1)&&(length(refNames) == 1)&&(length(noiseNames) == 1)% && (length(covarNames) == 1)
  % if there is nothing to choose (i.e. there are not multiple mask and covar, then just select the default)
  params = mrParamsDefault(paramsInfo);
else
  % otherwise have the user choose
  params = mrParamsDialog(paramsInfo,'Select which mask file we want to use');
end
if isempty(params),return;end

% get whcih mask and covar to use
for i = 1:length(epiNums)
  maskNums(i) = find(strcmp(params.maskFile{i},maskNames));
  noiseNums(i) = find(strcmp(params.noiseFile{i},noiseNames));
  refNums(i) = find(strcmp(params.refFile{i},refNames));
  % covarNums(i) = find(strcmp(params.covarFile{i},covarNames));
end

%%%%%%%%%%%%%%%%%%%%%%%
%%   checkForPeaks   %%
%%%%%%%%%%%%%%%%%%%%%%%
function epiNumsWithPeaks = checkForPeaks(fidList,epiNums)

passedCheck = ones(1,length(epiNums));
for i = 1:length(epiNums)
  % shortcut
  fid = fidList{epiNums(i)};
  % check for car/ext
  if ~all(fid.hasCarExt)
    % display what is missing
    filenames = {'car','ext'};
    for j = 1:length(filenames)
      if ~fid.hasCarExt(j)
	disp(sprintf('%s: Missing %s file',fid.filename,filenames{j}));
      end
    end
  end
  % check for peak files
  if ~all(fid.hasPeakFiles)
    passedCheck(i) = 0;
    % display what is missing
    filenames = {'acq.peak.bit','cardio.peak.bit','respir.peak.bit'};
    for j = 1:length(filenames)
      if ~fid.hasPeakFiles(j)
	disp(sprintf('%s: Missing %s file (need to run peak)',fid.filename,filenames{j}));
      end
    end
  end
end

scansThatPassed = find(passedCheck);
epiNumsWithPeaks = [];
for i = 1:length(scansThatPassed)
    epiNumsWithPeaks(end+1) = epiNums(scansThatPassed(i));
end

%%%%%%%%%%%%%%%%%%%%
%%   dofmrigru1   %%
%%%%%%%%%%%%%%%%%%%%
function dofmrigru1

% get the current directory
expdir = getLastDir(pwd);

% location of car/ext and fid files. Should be a directory
% in there that has the same name as the current directory
% i.e. s00120090706 that contains the fid files and the
% car/ext files
global fiddir;
fiddir = fullfile(fiddir,expdir);
if ~isdir(fiddir)
  disp(sprintf('(dofmrigru1) Could not find fid directory %s',fiddir));
  return
end

% now get info about fids
[fidList fidListArray] = getFileList(fiddir,'fid');
fidList = getFidInfo(fidList);
fidList = sortFidList(fidList);

% get list of epi scans
epiNums = getEpiScanNums(fidList);
if isempty(epiNums)
  disp(sprintf('(dofmrigru1) Could not find any epi files in %s',fiddir));
  return
end

% get anatomy scan nums
anatNums = getAnatScanNums(fidList);

% get sense noise/ref scans
[senseNoiseNums senseRefNums] = getSenseNums(fidList);

% find car/ext files
carList = getFileList(fiddir,'car','ext');
carList = getCarInfo(carList);
if isempty(carList)
  disp(sprintf('(dofmrigru1) Could not find any car/ext files in %s',fiddir));
  return
end

% find pdf files
pdfList = getFileList(fiddir,'pdf');

% get stimfile list
stimfileList = getFileList(fiddir,'mat');

% display what we found
dispList(fidList,epiNums,sprintf('Epi scans: %s',fiddir));
dispList(fidList,anatNums,sprintf('Anatomy scans: %s',fiddir));
dispList(fidList,senseRefNums,sprintf('Sense reference scan: %s',fiddir));
dispList(fidList,senseNoiseNums,sprintf('Sense noise scan: %s',fiddir));
dispList(carList,[],sprintf('Car/Ext files: %s',fiddir));
dispList(pdfList,[],sprintf('PDF files: %s',fiddir));
dispList(stimfileList,[],sprintf('Stimfiles: %s',fiddir));

% go find the matching car files for each scan
carMatchNum = getCarMatch(carList,fidList,epiNums);
if isempty(carMatchNum),return,end

% setup directories etc.
doMoveFiles(1,fidList,carList,pdfList,stimfileList,carMatchNum,epiNums,anatNums,senseNoiseNums,senseRefNums);

% now ask the user if they want to continue, because now we'll actually copy the files and set everything up.
if ~askuser('OK to run above commands?'),return,end
% now do it
fidList = doMoveFiles(0,fidList,carList,pdfList,stimfileList,carMatchNum,epiNums,anatNums,senseNoiseNums,senseRefNums);

% process ref and anatomy fid to make the mask
command = sprintf('cd Pre;'); eval(command);% move into Pre
global maskdir;
% location of masks
% make new empty mask directory in Pre
makeEmptyMLRDir('Mask');
maskdir = fullfile(pwd,'Mask');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for i = 1:length(anatNums)
  disp(sprintf('=============================================='));
  disp(sprintf('Convert anatomy to nifti and copy into maskdir'));
  disp(sprintf('=============================================='));
  % convert anatomy to nifti
  command = sprintf('fid2nifti %s;',fidList{anatNums(i)}.filename);
  eval(command);
  % move into emptyMLR directory
  command = sprintf('copyfile %s %s;',setext(fidList{anatNums(i)}.filename,'hdr'),fullfile(maskdir,'Anatomy'));
  eval(command);
  command = sprintf('copyfile %s %s;',setext(fidList{anatNums(i)}.filename,'img'),fullfile(maskdir,'Anatomy'));
  eval(command);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for i = 1:length(senseRefNums)
  disp(sprintf('=============================================='));
  disp(sprintf('Convert ref to nifti and copy into maskdir'));
  disp(sprintf('=============================================='));
  % convert ref to nifti
  fid2nifti(fidList{senseRefNums(i)}.filename);
  
  % move into emptyMLR directory for mask
  command = sprintf('movefile %s %s;',setext(fidList{senseRefNums(i)}.filename,'hdr'),maskdir);
  eval(command);
  command = sprintf('movefile %s %s;',setext(fidList{senseRefNums(i)}.filename,'img'),maskdir);
  eval(command);

end  
% move out of Pre
command = sprintf('cd ..;'); eval(command);


%%%%%%%%%%%%%%%%%%%%%
%%   doMoveFiles   %%
%%%%%%%%%%%%%%%%%%%%%
function fidList = doMoveFiles(justDisplay,fidList,carList,pdfList,stimfileList,carMatchNum,epiNums,anatNums,senseNoiseNums,senseRefNums)

% some command names
global epirri;
global postproc;

disp(sprintf('=============================================='));
disp(sprintf('Making directories'));
disp(sprintf('=============================================='));

% list of directories to make
dirList = {'Etc','Pre','Doc','Pre/Aux'};

% make them
for i = 1:length(dirList)
  if ~isdir(dirList{i})
    command = sprintf('mkdir(''%s'');',dirList{i});
    if justDisplay,disp(command),else,eval(command),end
  end
end

disp(sprintf('=============================================='));
disp(sprintf('Copying pdf files'));
disp(sprintf('=============================================='));

% move all the pdf files into the directory
for i = 1:length(pdfList)
  command = sprintf('copyfile %s %s',pdfList{i}.fullfile,fullfile('Doc',pdfList{i}.filename));
  if justDisplay,disp(command),else,eval(command),end
end

disp(sprintf('=============================================='));
disp(sprintf('Copying stimfiles'));
disp(sprintf('=============================================='));

% move stimfiles
for i = 1:length(stimfileList)
  command = sprintf('copyfile %s %s',stimfileList{i}.fullfile,fullfile('Etc',stimfileList{i}.filename));
  if justDisplay,disp(command),else,eval(command),end
end

if justDisplay,disp(sprintf('+++++++'));end

disp(sprintf('=============================================='));
disp(sprintf('Copying fid files'));
disp(sprintf('=============================================='));

% move fid directories
allUsefulFids = [epiNums anatNums senseNoiseNums senseRefNums];
for i = 1:length(fidList)
  % not a useful scan, put it in Pre/Aux
  if ~any(i==allUsefulFids)
    command = sprintf('copyfile %s %s',fidList{i}.fullfile,fullfile('Pre/Aux',setext(fixBadChars(stripext(fidList{i}.filename),{'.','_'}),'fid')));
    if justDisplay,disp(command),else,eval(command),end
  %otherwise put it in Pre
  else
    command = sprintf('copyfile %s %s',fidList{i}.fullfile,fullfile('Pre',setext(fixBadChars(stripext(fidList{i}.filename),{'.','_'}),'fid')));
    if justDisplay,disp(command),else,eval(command),end
  end
end

disp(sprintf('=============================================='));
disp(sprintf('Copying car/ext files'));
disp(sprintf('=============================================='));

% move car/ext files into fid directories
for i = 1:length(carMatchNum)
  command = sprintf('copyfile %s %s',carList{carMatchNum(i)}.fullfile,fullfile('Pre',setext(fixBadChars(stripext(fidList{epiNums(i)}.filename),{'.','_'}),'fid')));
  if justDisplay,disp(command),else,eval(command),end
  command = sprintf('copyfile %s %s',fullfile(carList{carMatchNum(i)}.path,carList{carMatchNum(i)}.extfilename),fullfile('Pre',setext(fixBadChars(stripext(fidList{epiNums(i)}.filename),{'.','_'}),'fid')));
  if justDisplay,disp(command),else,eval(command),end
end



disp(sprintf('=============================================='));
disp(sprintf('Processing epi files'));
disp(sprintf('=============================================='));

command = sprintf('cd Pre');
if justDisplay,disp(command),else,eval(command),end

% run epirri on all scans and sense noise/ref 
allScanNums = [epiNums senseNoiseNums senseRefNums];
for i = 1:length(allScanNums)
  command = sprintf('system(''%s %s 1 1 2 0 1 0'')',epirri,setext(fixBadChars(stripext(fidList{allScanNums(i)}.filename),{'.','_'}),'fid'));
  if justDisplay,disp(command),else,eval(command),end
end

% convert sense noise/ref into edt files
senseNums = [senseNoiseNums senseRefNums];
for i = 1:length(senseNums)
  %make fid to edt
  command = sprintf('system(''%s -intype 0 -outtype 1 %s %s'')',postproc,setext(fixBadChars(stripext(fidList{senseNums(i)}.filename),{'.','_'}),'fid'),setext(fixBadChars(stripext(fidList{senseNums(i)}.filename),{'.','_'}),'edt'));
  if justDisplay,disp(command),else,eval(command),end
end

command = sprintf('cd ..');
if justDisplay,disp(command),else,eval(command),end

%fix bad chars of names
for i = 1:length(fidList)
    fidList{i}.filename = setext(fixBadChars(stripext(fidList{i}.filename),{'.','_'}),'fid');
end
disp(sprintf('=============================================='));
disp(sprintf('DONE moving files. Now make emptyMLRDir -> call it ''Mask'''));
disp(sprintf('=============================================='));

%%%%%%%%%%%%%%%%%%%%%
%%   getCarmatch   %%
%%%%%%%%%%%%%%%%%%%%%
function carMatchNum = getCarMatch(carList,fidList,epiNums);

carMatchNum = [];

% get the names of the car files
for i = 1:length(carList)
  carNames{i} = carList{i}.filename;
end

% get info from scans
for i = 1:length(epiNums)
  scanNames{i} = stripext(fidList{epiNums(i)}.filename);
  carMatchNames{i} = putOnTopOfList(carNames{min(i,end)},carNames);
  startTime{i} = fidList{epiNums(i)}.startTimeStr;
  endTime{i} = fidList{epiNums(i)}.endTimeStr;
end

% make an mrParamsDialog where you can select
paramsInfo{1} = {'scanNum',1,'round=1','incdec=[-1 1]',sprintf('minmax=[1 %i]',length(epiNums))};
paramsInfo{2} = {'scanName',scanNames,'group=scanNum','type=String','editable=0'};
paramsInfo{3} = {'startTime',startTime,'group=scanNum','type=String','editable=0'};
paramsInfo{4} = {'endTime',endTime,'group=scanNum','type=String','editable=0'};
paramsInfo{5} = {'carFile',carMatchNames,'group=scanNum'};

% put out the dialog
params = mrParamsDialog(paramsInfo,'Match the car file with the scan');
if isempty(params),return;end

% now get the matching numbers
for i = 1:length(params.carFile)
    carMatchNum(i) = find(strcmp(params.carFile(i),carNames));
end


%%%%%%%%%%%%%%%%%%%%%%
%%   dispScanlist   %%
%%%%%%%%%%%%%%%%%%%%%%
function dispStr = dispList(fidList,nums,name)

% empty nums means to display all
if isempty(nums),nums = 1:length(fidList);end

dispStr = {};
disp(sprintf('============================='));
disp(sprintf('%s',name));
disp(sprintf('============================='));
for i = 1:length(nums)
  if isfield(fidList{nums(i)},'dispstr')
    disp(fidList{nums(i)}.dispstr);
  else
    disp(fidList{nums(i)}.filename);
  end
end

%%%%%%%%%%%%%%%%%%%%
%%   sortFidList  %%
%%%%%%%%%%%%%%%%%%%%
function fidList = sortFidList(fidList)

% sort by time stamp from log file
for i = 1:length(fidList)
  for j = 1:length(fidList)-1
    if fidList{j}.startTime > fidList{j+1}.startTime
      temp = fidList{j};
      fidList{j} = fidList{j+1};
      fidList{j+1} = temp;
    end
  end
end
%%%%%%%%%%%%%%%%%%%%
%%   getCarInfo   %%
%%%%%%%%%%%%%%%%%%%%
function carList = getCarInfo(carList)

disppercent(-inf,'(dofmrigru1) Get car info');
for i = 1:length(carList)
  disppercent(i/length(carList));
  carList{i}.car = readcar(carList{i}.fullfile);
  carList{i}.ext = readext(fullfile(carList{i}.path,carList{i}.extfilename));
  carList{i}.dispstr = sprintf('%s',carList{i}.filename);
end
disppercent(inf);
%%%%%%%%%%%%%%%%%%%%
%%   getFidInfo   %%
%%%%%%%%%%%%%%%%%%%%
function fidList = getFidInfo(fidList)

nVols = [];
disppercent(-inf,'(dofmrigru1) Getting fid info');
for i = 1:length(fidList)
  disppercent(i/length(fidList));
  % read the procpar
  fidList{i}.procpar = readprocpar(fidList{i}.fullfile);
  % get info using fid2xform if we can
  if isfield(fidList{i}.procpar,'ni')
    [fidList{i}.xform fidList{i}.info] = fid2xform(fidList{i}.procpar,-1);
  else
    fidList{i}.xform = [];fidList{i}.info = [];
  end
  % load the logfile
  log = 0;
  if isfile(fullfile(fidList{i}.fullfile,'log'))
    f = fopen(fullfile(fidList{i}.fullfile,'log'));
    thisline = fgets(f);
    [fidList{i}.startTime fidList{i}.startTimeStr] = getDatenumFromLogLine(thisline);
    thisline = fgets(f);
    [fidList{i}.endTime fidList{i}.endTimeStr] = getDatenumFromLogLine(thisline);
    fclose(f);
    log = 1;
  end
  % make the display string
  fidList{i}.dispstr = sprintf('%s: ',fidList{i}.filename);
  fidList{i}.dispstr = sprintf('%s%s->%s',fidList{i}.dispstr,fidList{i}.startTimeStr,fidList{i}.endTimeStr);
  if ~isempty(fidList{i}.info)
    fidList{i}.dispstr = sprintf('%s [%i %i %i %i] [%0.1f %0.1f %0.1f]',fidList{i}.dispstr,fidList{i}.info.dim(1),fidList{i}.info.dim(2),fidList{i}.info.dim(3),fidList{i}.info.dim(4),fidList{i}.info.voxsize(1),fidList{i}.info.voxsize(2),fidList{i}.info.voxsize(3));
     if ~isempty(fidList{i}.info.accFactor)
      fidList{i}.dispstr = sprintf('%s x%i',fidList{i}.dispstr,fidList{i}.info.accFactor);
     end
  end
  fidList{i}.hasCarExt = [0 0];
  fidList{i}.hasPeakFiles = [0 0 0];
  if ~isempty(dir(fullfile(fidList{i}.fullfile,'*.car')))
    fidList{i}.hasCarExt(1) = 1;
  end
  if ~isempty(dir(fullfile(fidList{i}.fullfile,'*.ext')))
    fidList{i}.hasCarExt(2) = 1;
  end
  if isfile(fullfile(fidList{i}.fullfile,'acq.peak.bit'))
    fidList{i}.hasPeakFiles(1) = 1;
  end
  if isfile(fullfile(fidList{i}.fullfile,'cardio.peak.bit'))
    fidList{i}.hasPeakFiles(2) = 1;
  end
  if isfile(fullfile(fidList{i}.fullfile,'respir.peak.bit'))
    fidList{i}.hasPeakFiles(3) = 1;
  end
end
disppercent(inf);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   getDatenumFromLogLine   %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [thisDatenum thisDatestr]= getDatenumFromLogLine(thisline)

thisDatenum = 0;thisDatestr = '';
if ~isempty(thisline)
  splitThisLine = strfind(thisline,': ');
  if ~isempty(splitThisLine)
    thisline = thisline(1:splitThisLine-1);
    [dow month day hhmmss year] = strread(thisline,'%s %s %s %s %s');
    thisDatestr = sprintf('%s-%s-%s %s',day{1},month{1},year{1},hhmmss{1});
    thisDatenum = datenum(thisDatestr);
  end
end

%%%%%%%%%%%%%%%%%%%%%%
%%   getSenseNums   %%
%%%%%%%%%%%%%%%%%%%%%%
function [senseNoiseNums senseRefNums] = getSenseNums(fidList)

senseNoiseNums = [];senseRefNums = [];

for i = 1:length(fidList)
  if ~isempty(fidList{i}.info)
    % make sure this is not a 3d acq or a sense
    if ~fidList{i}.info.acq3d && (fidList{i}.info.accFactor == 1)
      if ~isempty(strfind(fidList{i}.filename,'noise'))
	senseNoiseNums(end+1) = i;
      elseif ~isempty(strfind(fidList{i}.filename,'ref'))
	senseRefNums(end+1) = i;
      end
    end
  end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   getSenseScanNums   %%
%%%%%%%%%%%%%%%%%%%%%%%%%%
function senseNums = getSenseScanNums(fidList,epiNums)

senseNums = [];
for i = 1:length(epiNums)
  if ~isempty(fidList{epiNums(i)}.info)
    if ~isempty(fidList{epiNums(i)}.info.senseFactor)
      senseNums(end+1) = i;
    end
  end
end
%%%%%%%%%%%%%%%%%%%%%%%%
%%   getEpiScanNums   %%
%%%%%%%%%%%%%%%%%%%%%%%%
function epiNums = getEpiScanNums(fidList,nVolsCutoff)

if ieNotDefined('nVolsCutoff'),nVolsCutoff = 10;end

epiNums = [];
for i = 1:length(fidList)
  if ~isempty(fidList{i}.info)
    if fidList{i}.info.dim(4) > nVolsCutoff
      epiNums(end+1) = i;
    end
  end
end


%%%%%%%%%%%%%%%%%%%%%%%%%
%%   getAnatScanNums   %%
%%%%%%%%%%%%%%%%%%%%%%%%%
function anatNums = getAnatScanNums(fidList)

anatNums = [];
% look for 3D scans
for i = 1:length(fidList)
  if ~isempty(fidList{i}.info)
    % check for 3d scan
    if fidList{i}.info.acq3d
      % make sure it is not a raw scan
      if fidList{i}.info.dim(3) == length(fidList{i}.info.pss)
        anatNums(end+1) = i;
      end
    else
      % check for an anatomy sounding name (i.e. has the word "anat" in it
      if ~isempty(strfind(lower(fidList{i}.filename),'anat'))
	anatNums(end+1) = i;
      end
    end
  end
end

%%%%%%%%%%%%%%%%%%%%%
%%   getFileList   %%
%%%%%%%%%%%%%%%%%%%%%
function [fileList fileListArray] = getFileList(dirname,extList,matchExtList,filenameMatch)

fileList = {};fileListArray = {};

% make into a cell array
extList = cellArray(extList);

if ~ieNotDefined('matchExtList')
  matchExtList = cellArray(matchExtList);
else
  matchExtList = [];
end

% default to no filename matching 
if ieNotDefined('filenameMatch')
  filenameMatch = '';
else
  filenameMatch = cellArray(filenameMatch);
end

% open the directory
dirList = dir(dirname);
if isempty(dirList),return,end

% now go through the directory looking for matches
for i = 1:length(dirList)
  match = 0;
  % skip all . files
  if dirList(i).name(1) == '.',continue,end
  % skip all files that don't match the filename match if specified
  if ~isempty(filenameMatch)
    noFilenameMatch = 0;
    for j = 1:length(filenameMatch)
      if isempty(strfind(lower(dirList(i).name),lower(filenameMatch{j}))),noFilenameMatch=1;,end
    end
    if noFilenameMatch,continue,end
  end
  % get the file extension
  thisExt = getext(dirList(i).name);
  % check for match
   for j = 1:length(extList)
    if strcmp(extList{j},thisExt)
      % found the match
      if ~match
	% keep the name of the file
	fileList{end+1}.filename = dirList(i).name;
	fileListArray{end+1} = dirList(i).name;
	fileList{end}.fullfile = fullfile(dirname,dirList(i).name);
	fileList{end}.date = dirList(i).date;
	fileList{end}.datenum = dirList(i).datenum;
	% if we need to find matches
	if ~isempty(matchExtList)
	  fileList{end}.filename = dirList(i).name;
	  fileListArray{end+1} = dirList(i).name;
	  fileList{end}.fullfile = fullfile(dirname,dirList(i).name);
	  fileList{end}.path = dirname;
	  fileList{end}.(sprintf('%sfilename',extList{j})) = dirList(i).name;
	  % check for matching file
	  stemName = stripext(fullfile(dirname,dirList(i).name));
	  for k = 1:length(matchExtList)
	    if ~isfile(setext(stemName,matchExtList{j}))
	      disp(sprintf('(dofmrigru1:getFileList) No matching %s file for %s',matchExtList{j},dirList(i).name));
	    else
	      fileList{end}.(sprintf('%sfilename',matchExtList{j})) = setext(dirList(i).name,matchExtList{j});
	    end
	  end
	  
	end
      end
      match = 1;
    end
  end
end
