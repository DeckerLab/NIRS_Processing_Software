
%This script re-wreites the Stim markers in a Snrif file, based upon reading from an Excel worksheet
% Table must have these fields: 
%  EventID, EventName Onset_sec, Duration_sec, Keep_Extra_After, Exclude
% Events in hrd are filtered to retain only those that match the EventID and time frames in the
% tabEvents_ForSubject.  New events are created based on EventName (each orginal EventID may be changed to new
% EventID's based on providing distinct EventName values.    
% If there is a file with name like "truncation_mapping.mat" in the folder, it uses that to related the times
% in the Excel file to the new times in the truncated data.

%SubjectCodes = {'CB004','CB008','CB009','CB010','CB011','CB014','CB015','CB017','CB018','CB020','CB021','CB022','CB023','CB024','CB027'};
SubjectCodes = {'CB010','CB011','CB014','CB015','CB017','CB018','CB020','CB021','CB022','CB023','CB024','CB027'};
SubjectFolders = SubjectCodes; %can define specifically if folder names are not same as subject codes

ProcessingRoot= 'D:\NIRS Processing\NIRS Data\ROHC';
Snirf_RootFolder = [ProcessingRoot '\Homer'];
Events_ExcelFilename = [ProcessingRoot '\Analysis\ROHC Data Summary.xlsm'];
EventTimeTolerance_secs = 3;

opts = detectImportOptions(Events_ExcelFilename,'Sheet','Event Times');
opts=setvartype(opts,'Subject','categorical'); %change this column to categorical, to allow filtering
opts=setvartype(opts,'Exclude','char');  
tab_events = readtable(Events_ExcelFilename,opts);

% we need to delete any 'groupResults.mat' file, in the root folder if found
answer_delgroupesults = '';
groupresults_filename = [Snirf_RootFolder '\groupResults.mat'];
if isfile(groupresults_filename) 
    answer_delgroupesults = questdlg('OK to delete groupResults.mat in root folder from previous Homer3 processing?', ...
	'Confirm file deletion', ...
	'OK','OK for All','Cancel','OK for All');
    if (strcmp(answer_delgroupesults,'Cancel')); return; end
    delete(groupresults_filename);
end

for idx_subject=1:length(SubjectFolders)
    subject_code= SubjectCodes{idx_subject} ;
    
    disp(['Processing subject code: ' subject_code ]);
    Snirf_SubjectFolder = [Snirf_RootFolder '\' SubjectFolders{idx_subject}];
    
    tab_events_subject = tab_events(tab_events.Subject==subject_code,:);

    use_mapping = false;
    mapping_filename = [Snirf_SubjectFolder '\truncation_mapping.mat'];
    if isfile(mapping_filename)
        load(mapping_filename, 'mapping_data','mapping_events');   %presumably file was saved by NIRX_Truncate_toNirs.m script
        use_mapping=true;
    end

    % we also need to delete any 'groupResults.mat' file in the subject folder, if found
    groupresults_filename = [Snirf_SubjectFolder '\groupResults.mat'];
    if isfile(groupresults_filename) 
        if ~strcmp(answer_delgroupesults,'OK for All')
            answer_delgroupesults = questdlg(sprintf('OK to delete groupResults.mat in subject folder ''%s'' from previous Homer3 processing?',SubjectFolders{idx_subject}), ...
            'Confirm file deletion', ...
            'OK','OK for All','Cancel','OK for All');
            if (strcmp(answer_delgroupesults,'Cancel')); return; end
        end
        delete(groupresults_filename);
    end    
    
    disp ' - load Snirf'
    snirf_dir = dir([Snirf_SubjectFolder '\*.snirf']);
    if length(snirf_dir) ~= 1; error('ERROR: Expected to find one Snirf file, but found %d snirf files in folder: %s', length(snirf_dir), Snirf_SubjectFolder); end;
    snirf_filename = [Snirf_SubjectFolder '\' snirf_dir(1).name];
    snirf = SnirfLoad(snirf_filename);    
    
    Snirf_SetStims(snirf, tab_events_subject, mapping_data, mapping_events, EventTimeTolerance_secs, false);

    disp ' - save Snirf'
    SnirfSave( snirf_filename, snirf );
end
