%This script creates Snirf files (Homer-compatible files) from NIRx files.  It relies only on  .hdr, .wl1, .wl2 files.
%In the process of conversion, it will also truncate the data, as defined in an Excel worksheet.
%Files from separate subjects should be arranged in folders under one main folder.
%You must set the main folder of the NIRx-format subject folder; the path to the Snirf-format folders; and the path
%to the Excel workbook.  The Excel workbook must have a worksheet named "Event Times"; that worksheet must have
%at least these columns: Subject, EventID, EventName, Onset_sec, Duration_sec, Keep_Extra_After, Exclude


%SubjectCodes = {'CB004','CB008','CB009','CB010','CB011','CB014','CB015','CB017','CB018','CB020','CB021','CB022','CB023','CB024','CB027'};
SubjectCodes = {'CB027'};
SubjectFolders = SubjectCodes; %can define specifically if folder names are not same as subject codes


NIRx_RootFolder = 'D:\NIRS Processing\NIRS Data\ROHC\NIRx';
Nirs_RootFolder = 'D:\NIRS Processing\NIRS Data\ROHC\Homer';
Events_ExcelFilename = 'D:\NIRS Processing\NIRS Data\ROHC\Analysis\ROHC Data Summary.xlsm';
SD_File = 'D:\NIRS Processing\NIRS Data\ROHC\Homer\sdfile.sd';
    

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

%Check something in the events table. We want to make sure that there is 

for idx_subject=1:length(SubjectFolders)
    
    disp(['Processing subject code: ' SubjectCodes{idx_subject}  ]);
    
    NIRx_SubjectFolder = [NIRx_RootFolder '\' SubjectFolders{idx_subject}];
    %create destination folder if it doesn't exist
    Nirs_SubjectFolder = [Nirs_RootFolder '\' SubjectFolders{idx_subject}];
    if not(isfolder(Nirs_SubjectFolder))
        mkdir(Nirs_SubjectFolder)
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
    Snirf_SetStims(snirf, tab_events_subject, mapping_data, mapping_events, EventTimeTolerance_secs, false);

    Snirf_filename = [Nirs_SubjectFolder '\' SubjectCodes{idx_subject} '.snirf' ];
    disp(['   Saving Snirf as: '   Snirf_filename]);
    SnirfSave( Snirf_filename, snirf );
end
