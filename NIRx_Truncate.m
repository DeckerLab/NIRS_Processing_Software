function [mapping_data, mapping_events] = NIRx_Truncate(Nirs_foldername, tabEvents_ForSubject, KeepBefore_secs, KeepAfter_secs, EventTimeTolerance_secs)
    %Caller provides path to a folder with .hdr, .wl1, .wl2 files; and a
    %table that describes the Events and periods for which sections to 
    %retain.  Table must have these fields: 
    %  EventID, EventName Onset_sec, Duration_sec, Keep_Extra_After, Exclude
    % Events in hrd are filtered to retain only those that match the EventID and time frames in the
    % tabEvents_ForSubject.  New events are created based on EventName (each orginal EventID may be changed to new
    % EventID's based on providing distinct EventName values.    
    
    %Caller may also specify the amount of time to keep before and after an
    % event window (defaults to 2 and 10 seconds, respecively)
    %Return values are:
    %  mapping_data is vector that tells the index number in the truncated data for each old index (0 for rows that 
    %               were deleted).
    %  mapping_events is cell array; each element is a structure with the EventID value; and a 2-dim array, which 
    %              for each retained event shows the new event time (in seconds) and the row number in 
    %              tabEvents_ForSubject that was used to decide to retain the event.
	% some more coomment
    
    mapping_data = [];
    mapping_events={};
    
    if ~exist('Nirs_foldername','var')
       Nirs_foldername = uigetdir(pwd,'Select Nirs Data Folder...');
    end

    if ~exist('KeepBefore_secs','var')
        KeepBefore_secs = 2;
    end
    if ~exist('KeepAfter_secs','var')
        KeepAfter_secs = 10;
    end
    if ~exist('EventTimeTolerance_secs','var')
        EventTimeTolerance_secs = 2;  %an event is deemed to be in the user-entered windows if it is within 
        % this tolerance band (+/- seconds); So if user entered an event window at 60 seconds, and there is an 
        % event marker at 58.53 seconds with the expected EventID, we will assume this is a valid event
    end   
  
    %look for these files:
    % *.wl1
    % *.wl2
    % *.hdr

    
    % Read and interpret .hdr d ############################################
    % #########################################################################
    disp '   Loading header file ...'
    hdr_dir = dir([Nirs_foldername '/*.hdr']);
    if length(hdr_dir) == 0; error('ERROR: Cannot find NIRx header file in selected directory...'); end;
    hdr_filename = [Nirs_foldername '/' hdr_dir(1).name];
    fid = fopen(hdr_filename);
    tmp = textscan(fid,'%s','delimiter','\n');  %This just reads every line
    hdr_str = tmp{1};
    fclose(fid);

    
    % Load wavelength d
    % #######################################################################
    disp '   Loading wave data 1...'
    wl1_dir = dir([Nirs_foldername '\*.wl1']);
    if isempty(wl1_dir); error('ERROR: Cannot find NIRx .wl1 file in selected directory...'); end;
    wl1_filename = [Nirs_foldername '/' wl1_dir(1).name];
    wl1 = load(wl1_filename);

    disp '   Loading wave data 2...'
    wl2_dir = dir([Nirs_foldername '\*.wl2']);
    if isempty(wl2_dir); error('ERROR: Cannot find NIRx .wl2 file in selected directory...'); end;
    wl2_filename = [Nirs_foldername '/' wl2_dir(1).name];
    wl2 = load(wl2_filename);
    wl1_2=[wl1 wl2];
    
    %Find Sample rate
    keyword = 'SamplingRate=';
    tmp = strfind(hdr_str,keyword);
    eventsection_start = find(~cellfun(@isempty,tmp)); %This gives cell of hdr_str with keyword
    tmp = hdr_str{eventsection_start};
    sampling_freq = str2double(tmp(length(keyword)+1:end));


    %build a logical vector of datapoints to keep
    datacount = size(wl1_2,1);
    datarows_tokeep = zeros(datacount,1);
    for idx_hdrevent=1:size(tabEvents_ForSubject,1)
        keep_start_frame = round((tabEvents_ForSubject.Onset_sec(idx_hdrevent)-KeepBefore_secs)*sampling_freq)+1;
        keep_end_frame = keep_start_frame + round((tabEvents_ForSubject.Duration_sec(idx_hdrevent) + ...
                                                   tabEvents_ForSubject.Keep_Extra_After(idx_hdrevent) + ...
                                                   KeepAfter_secs )*sampling_freq);
        datarows_tokeep(keep_start_frame:keep_end_frame)=1;
    end
    
    %now do arithmetic shift of data to make values line up across the deletions we are about to make
    keep_window_index = 0;
    mapping_data = zeros(datacount,1);
    in_window = false;
    new_index_counter = 0;
    for idx_hdrevent=1:datacount
        if (datarows_tokeep(idx_hdrevent)==1)
            new_index_counter = new_index_counter+1;
            mapping_data(idx_hdrevent)= new_index_counter;
        end
        if (~in_window && (datarows_tokeep(idx_hdrevent)==1))  %if just entered into a new keep window
            in_window=true;
            keep_window_index=keep_window_index+1;
            if (keep_window_index>1)  %only need to shift for windows starting at #2
                offset = startvals_nextwindow - wl1_2(idx_hdrevent,:);
                wl1_2(idx_hdrevent:datacount,:) = wl1_2(idx_hdrevent:datacount,:) + offset;
            end
        else
            if (in_window && (datarows_tokeep(idx_hdrevent)==0))  %if just ended a keep window
                in_window=false;
                startvals_nextwindow = wl1_2(idx_hdrevent,:);  %actually this is the row after the keep window.  These are the target values for the first row of next window
            end
        end
    end
    
    wl1_2(datarows_tokeep==0,:) = [];   %delete unwanted data rows
    
    %filter and shift Event Markers in header file
    keyword = 'Events="#';
    tmp = strfind(hdr_str,keyword);
    eventsection_start = find(~cellfun(@isempty,tmp)) + 1; %This gives cell of hdr_str with keyword
    tmp = strfind(hdr_str(eventsection_start:end),'#');  %was strfind(hdr_str(eventsection_start+1:end),'#')  but the '+1' was cauaing an error when there are no events in the file
    eventsection_end = find(~cellfun(@isempty,tmp)) - 1;
    eventsection_end = eventsection_start + eventsection_end(1);
    hdr_events = cell2mat(cellfun(@str2num,hdr_str(eventsection_start:eventsection_end),'UniformOutput',0));
    if size(hdr_events,1)>0  %if the file has zero recorded events, don't bother to edit
        keep_event = zeros(size(hdr_events,1),1);
        map_DissallowEventUntilTime = containers.Map('KeyType','int32','ValueType','double');
        EventID_max = max(tabEvents_ForSubject.EventID);
        for idx_hdrevent=1:size(hdr_events,1)
            this_EventID=hdr_events(idx_hdrevent,2);
            this_StartFrame=hdr_events(idx_hdrevent,3);
            this_StartSec = (this_StartFrame-1)/sampling_freq;
            for idx_eventtable=1:size(tabEvents_ForSubject,1)
                this_keep = (this_EventID==(tabEvents_ForSubject.EventID(idx_eventtable))) && ...
                        (abs(this_StartSec- tabEvents_ForSubject.Onset_sec(idx_eventtable))<= EventTimeTolerance_secs) && ...
                        (this_StartSec<(tabEvents_ForSubject.Onset_sec(idx_eventtable)+tabEvents_ForSubject.Duration_sec(idx_eventtable))) && ...
                        isempty(tabEvents_ForSubject.Exclude{idx_eventtable}) && ...
                        datarows_tokeep(this_StartFrame)==1 ;  %check if this is an event in user-declared list, and make sure that this data was retained
                if this_keep && map_DissallowEventUntilTime.isKey(this_EventID) && (this_StartSec<map_DissallowEventUntilTime(this_EventID) )
                    %this prevents keeping a second event of the same type within
                    % the time duration window of the first event
                    this_keep = false;
                end

                if this_keep
                    keep_event(idx_hdrevent)=1;

                    this_EventName = tabEvents_ForSubject.EventName{idx_eventtable};

                    event_frame_original = this_StartFrame;  
                    event_time_original = this_StartSec;

                    %record the mapping of this retained event
                    idx_e = 0;
                    %try to find a mapping entry with this EventID and EventName
                    bln_EventID_Original_InMapping = false;
                    for idx_e_search = 1:length(mapping_events)
                        if (mapping_events{idx_e_search}.EventID_Original == this_EventID) 
                            bln_EventID_Original_InMapping = true;   %We have found this EventID; so if we don't also 
                               %find this EventName, we will need to assign a new EventID
                            if strcmp(mapping_events{idx_e_search}.EventName, this_EventName)
                                idx_e = idx_e_search;
                                break;
                            end
                        end
                    end    
                    if idx_e==0   %this EventID & EventName not yet in the mapping collection
                       e.EventID_Original = this_EventID;
                       if bln_EventID_Original_InMapping
                            e.EventID_New = EventID_max + 1;
                            EventID_max = e.EventID_New; 
                       else
                            e.EventID_New = this_EventID;
                       end
                       e.EventName = this_EventName;
                       e.mapping = [];
                       mapping_events{1,length(mapping_events)+1} = e;  %add this structure into the collection
                       idx_e = length(mapping_events);
                    else
                       e=mapping_events{idx_e};
                    end

                    event_frame_new = mapping_data(event_frame_original);
                    event_time_new = round((event_frame_new-1)/sampling_freq,2);
                    mapping_events{1,idx_e}.mapping = cat(1,mapping_events{1,idx_e}.mapping, ...
                                        [event_frame_original event_time_original event_frame_new event_time_new idx_eventtable]);  %add into the mapping array 
                    %the original frame, new frame, new time of this event and the row in the user event table that was used to qualify the event

                    %adjust time of event in the header data
                    hdr_events(idx_hdrevent,1) = event_time_new;
                    hdr_events(idx_hdrevent,2) = e.EventID_New;
                    hdr_events(idx_hdrevent,3) = event_frame_new;

                    map_DissallowEventUntilTime(this_EventID) = this_StartSec + tabEvents_ForSubject.Duration_sec(idx_eventtable);
                    break;
                end 
            end
        end

        hdr_events(keep_event==0,:)=[];  %delete the events we dont want
        eventlines=cell(size(hdr_events,1),1);
        for idx_hdrevent=1:size(hdr_events,1)
            eventlines(idx_hdrevent)={strjoin([compose('%.2f',hdr_events(idx_hdrevent,1))  compose('%d',hdr_events(idx_hdrevent,2)) compose('%d',hdr_events(idx_hdrevent,3))],'\t')};
        end

        disp '   writing edited header...'
        %stick the edited events into the file
        hdr_str = [hdr_str(1:eventsection_start-1,1); eventlines; hdr_str(eventsection_end+1:end)];
        %rewrite the header file
        fid = fopen(hdr_filename,'w');
        fprintf(fid,'%s\n',hdr_str{:});
        fclose(fid);    
    end

    disp '   writing edited wavelengths...'
    %rewrite wavelength files
    wl1=wl1_2(:,1:size(wl1,2));
    wl2=wl1_2(:,size(wl1,2)+1:end);
    
    writematrix(wl1,wl1_filename,'Delimiter','space','FileType','text');
    writematrix(wl2,wl2_filename,'Delimiter','space','FileType','text');
   
end