%This script creates Snirf files (Homer-compatible files) from NIRx files.  It relies only on  .hdr, .wl1, .wl2 files.
%In the process of conversion, it will also truncate the data, as defined in an Excel worksheet.
%Files from separate subjects should be arranged in folders under one main folder.
%You must set the main folder of the NIRx-format subject folder; the path to the Snirf-format folders; and the path
%to the Excel workbook.  The Excel workbook must have a worksheet named "Event Times"; that worksheet must have
%at least these columns: Subject, EventID, EventName, Onset_sec, Duration_sec, Keep_Extra_After, Exclude

ProcessingRoot= 'D:\NIRS Processing\NIRS Data\ROHC';
%ProcessingRoot= 'D:\NIRS_Data\Randolph';

SelectFoldersByPattern = false; %if you set to true, you can use the SelectFolders_SearchPattern pattern to select all 
        % matching folders for processing.  If set to false, you must manually set the SubjectFolders list below.

allow_unmatched_events = false;  %set this to 'true' if the original HDR file does not contain proper event
            % markers at the times that you want to truncate around and/or set your new events.
        
SelectFolders_SearchPattern = 'CB*';  
NIRx_RootFolder = [ProcessingRoot '\NIRx'];
Nirs_RootFolder = [ProcessingRoot  '\Homer'];
Events_ExcelFilename = [ProcessingRoot '\Analysis\ROHC Data Summary.xlsx'];
SD_File = [ProcessingRoot '\Homer\sdfile.sd'];

if SelectFoldersByPattern
    SubjectFolders = {};
    dir_result = dir([NIRx_RootFolder '\' SelectFolders_SearchPattern]);
    for i=1:size(dir_result,1)
        if dir_result(i).isdir
            SubjectFolders{1,length(SubjectFolders)+1} = dir_result(i).name;
        end
    end
    
    userresponse  = questdlg(sprintf(['Are you sure you want to truncate & convert all %d subject folders in the NIRX folder?\n' ...
              'This is typically only required if you are have modified the timing of truncation periods, or you are reprocessing the entire dataset.'], length(SubjectFolders)), ...
	'Truncate/convert all NIRX files?', ...
	'OK','Cancel','Cancel');
    if strcmp(userresponse,'Cancel'); return; end
else
    
    %define here if you want to manually define the folders to process.
    
%     SubjectFolders = {'CB004','CB008','CB009','CB010','CB011','CB014','CB015','CB017','CB018','CB020', ...
%                     'CB021','CB022','CB023','CB024','CB027','CB026','CB029','CB030','CB031'};

    %Typically you only need to specify the new datasets that need to be truncated, not the entire group.
    SubjectFolders = {'CB026','CB029','CB030','CB031'};
end

SubjectCodes = SubjectFolders; %can define specifically if folder names are not same as subject codes
    
KeepBefore_secs = 2;
KeepAfter_secs = 15;
EventTimeTolerance_secs = 3;

% if ~exist('Events_ExcelFilename','var')
%     [file,path] = uigetfile({'*.xls;*.xlsb;*.axlsm;*.xlsx',...
%              'Excel Workbook (*.xls,*.xlsb,*.xlsm,*.xlsx)'},'Select Excel Events file...');
%    Events_ExcelFilename = [path file];    
% end    

opts = detectImportOptions(Events_ExcelFilename,'Sheet','Event Times');
opts=setvartype(opts,'Subject','categorical'); %change this column to categorical, to allow filtering
opts=setvartype(opts,'Exclude','char');  
tab_events = readtable(Events_ExcelFilename,opts);
response_ExcludedEvents='';

% we need to delete any 'groupResults.mat' file, in the root folder if found
answer_delgroupesults = '';
groupresults_filename = [Nirs_RootFolder '\groupResults.mat'];
if isfile(groupresults_filename) 
    answer_delgroupesults = questdlg(sprintf('OK to delete groupResults.mat in root folder from previous Homer3 processing? \nThis is required to avoid conflicts with previous processing.'), ...
	'Confirm file deletion', ...
	'OK','OK for All','Cancel','OK for All');
    if (strcmp(answer_delgroupesults,'Cancel')); return; end
    delete(groupresults_filename);
end


for idx_subject=1:length(SubjectFolders)
    
    disp(['Processing subject code: ' SubjectCodes{idx_subject}  ]);
    
    NIRx_SubjectFolder = [NIRx_RootFolder '\' SubjectFolders{idx_subject}];
    %create destination folder if it doesn't exist
    Nirs_SubjectFolder = [Nirs_RootFolder '\' SubjectFolders{idx_subject}];
    if not(isfolder(Nirs_SubjectFolder))
        mkdir(Nirs_SubjectFolder)
    end

    % we also need to delete any 'groupResults.mat' file in the subject folder, if found
    groupresults_filename = [Nirs_SubjectFolder '\groupResults.mat'];
    if isfile(groupresults_filename) 
        if ~strcmp(answer_delgroupesults,'OK for All')
            answer_delgroupesults = questdlg(sprintf('OK to delete groupResults.mat in subject folder ''%s'' from previous Homer3 processing?  This is required to avoid conflicts with previous processing.',SubjectFolders{idx_subject}), ...
            'Confirm file deletion', ...
            'OK','OK for All','Cancel','OK for All');
            if (strcmp(answer_delgroupesults,'Cancel')); return; end
        end
        delete(groupresults_filename);
    end       
    
    %copy wl1, wl2, and hdr files
    copystatus = copyfile(strcat(NIRx_SubjectFolder, '\*.hdr'), Nirs_SubjectFolder);
    if (copystatus==0); error(strcat('ERROR: Cannot find NIRx header file in NIRx subject folder: ',NIRx_SubjectFolder )); end
    copystatus = copyfile(strcat(NIRx_SubjectFolder, '\*.wl?'), Nirs_SubjectFolder);
    if (copystatus==0); error(strcat('ERROR: Cannot find NIRx wavelength data file in NIRx subject folder: ',NIRx_SubjectFolder )); end

    %check that there is one of each file type
    extensions = {'.hdr','.wl1','.wl2'};
    for i=1:3
        dirfiles = dir([Nirs_SubjectFolder '\*' extensions{i} ]);
        if isempty(dirfiles)
            error(['ERROR: Did not find ' extensions{i} ' file in the folder: ' Nirs_SubjectFolder]); 
        elseif length(dirfiles)>1
            error(['ERROR: Found multiple ' extensions{i} ' files in the folder: ' Nirs_SubjectFolder]); 
        end
    end
    
    tab_events_subject = tab_events(tab_events.Subject==SubjectCodes{idx_subject},:);
    
    if (length([tab_events_subject.Exclude{:}])>0) && (~strcmp(response_ExcludedEvents,'OK for all'))
        response_ExcludedEvents = questdlg(sprintf(['For subject ''%s'' the ''Event Times'' worksheet indicates some excluded events.\n' ...
            'If you truncate using Excluded events, you will not be able to later reprocess using those events.\n' ...
            'OK to proceed?'], SubjectCodes{idx_subject}), ...
            'Truncating with Excluded Events', ...
            'OK','OK for all','Abort','Abort');
            if (strcmp(response_ExcludedEvents,'Abort'))
                return;  %Abort
            end      
    end
    
    
    disp ' - truncating data'
    [mapping_data, mapping_events] = NIRx_Truncate(Nirs_SubjectFolder, tab_events_subject, KeepBefore_secs, KeepAfter_secs, EventTimeTolerance_secs);
    %save the mapping from old to new index values and events
    save([Nirs_SubjectFolder '\truncation_mapping.mat'],'mapping_data','mapping_events','-mat');  %could save as ASCII if needed, but 40 times bigger file
    
    disp ' - converting to Nirs'
    Nirs_filename = [Nirs_SubjectFolder '\' SubjectCodes{idx_subject} '.nirs' ];
    NIRx2nirs(Nirs_SubjectFolder,SD_File,Nirs_filename);
    
    
    disp ' - create Snirf'
    snirf= SnirfClass(load(Nirs_filename,'-mat'));
    %edit the stims to assign proper names and durations
    Snirf_SetStims(snirf, tab_events_subject, mapping_data, mapping_events, EventTimeTolerance_secs, allow_unmatched_events);

    Snirf_filename = [Nirs_SubjectFolder '\' SubjectCodes{idx_subject} '.snirf' ];
    disp(['   Saving Snirf as: '   Snirf_filename]);
    SnirfSave( Snirf_filename, snirf );
end
