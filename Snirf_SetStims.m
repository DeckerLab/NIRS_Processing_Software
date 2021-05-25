function Snirf_SetStims(snirf, tab_events_subject, mapping_data, mapping_events, eventime_tolerance_sec, allow_unmatched_events)
    %This function deletes the exisiting events in the snirf.stim array and recreates them, as specified by the 
    % "tab_events_subject" which is a table that includes at least the following columns: 
    %   Subject, EventID, EventName Onset_sec, Duration_sec, EventName, Exclude
    % New events are created based on EventName (each orginal EventID may be changed to new
    % EventID's based on providing distinct EventName values).    
    
    % Optional params "mapping_data" and "mapping_events": if the data was
    % truncated, the time values in the tab_events_subject are presumed to
    % refer to the original data, not the truncated data.  Therefore the
    % "mapping_data" is used to compute the frame (and time) in the
    % truncated data.
    % If supplied the "mapping_events" is used to get the
    % exact timing mark: for example, if the tab_events_subject specifies that an event
    % with EventID=2 should happen at 80 seconds, the "mapping_events" is
    % searched for an event that had an orgiginal EventID=2, and an
    % original (pre-truncation) time of approximately 80 seconds; the
    % tolerance for the time window is set default to 2 seconds.
    % "mapping_events" is a cell array of structures with following fields:
    %   EventID_Original: EventID in original data file and also in the tab_events_subject table
    %   mapping: 2D matix; each row represents one event; columns
    %             represent: [event_frame_original event_time_original event_frame_new event_time_new idx_eventtable] 
    %              (where idx_eventtable is the row number in the tab_events_subject used to qualify the
    %             event)
    % If you supply "mapping_events", you can also supply allow_unmatched_events; for an event specified in the    
    % tab_events_subject, if a matching event cannot be found in the mapping_events, this param controls whether an
    % event will be added nonetheless, or an error will be thrown.
    
    % Tod Flak 24-Mar-2021

    %NOTE: since 'snirf' is an object derived from 'handle' , it is passed
    %by reference.  Therefore we can make changes directly to the data in
    %the object to change the caller's version -- no need to copy, or to
    %pass back a copy of the argument.
    
    do_frame_shift= (exist('mapping_data','var') && ~isempty(mapping_data)) ;  %if param supplied, will use to compute frame shift
    matchto_original_event = (exist('mapping_events','var') && ~isempty(mapping_events));  %if param supplied, will use to get exact time mark of an event from original header file.
    
    if ~exist('eventime_tolerance_sec','var')
        eventime_tolerance_sec = 2;
    end
    if ~exist('allow_unmatched_events','var')
        allow_unmatched_events = false;
    end        

    %delete existing stim classes
    snirf.stim=[]; 
    
    map_stimname= containers.Map('KeyType','char','ValueType','int32');
    sampling_frequency = 1/snirf.data.time(2); %I've just realized that the snirf class does not include sampling frequency!
      % Instead, it just has all the time points in a vector data.time.  This is rather sloppy, but I'm just gonna
      % assume that this vector starts at zero, and is uniformly increasing.  Actually, I guess we can check to
      % make sure!
    delta = snirf.data.time(2:end) - snirf.data.time(1:(end-1));
    if (snirf.data.time(1)~=0 || (abs(max(delta)-min(delta))>1e-6) )   %instead of requiring max(delta)be identical to min(delta), just make sure they are really close!
        error('This function assumes that the snirf.data.time starts at 0 and increases uniformly.  This is not true for current snirf data, so it cannot be processed by this function as currently written.');
    end
    
    
    %go through Excel table, create new stim class as needed, and set onset, proper names and durations
    for idx_tabevents = 1:size(tab_events_subject,1)
        if strcmp(tab_events_subject.Exclude(idx_tabevents),'')
            event_name = tab_events_subject.EventName{idx_tabevents};
            event_id_original = tab_events_subject.EventID(idx_tabevents);
            
            if ~isKey(map_stimname,event_name)  %new event?
                if isempty(snirf.stim)
                    snirf.stim=[StimClass()];  %create a new one-element array of type StimClass   
                else
                    snirf.stim(1,length(snirf.stim)+1)=StimClass();  %add another
                end
                map_stimname(event_name)= length(snirf.stim);

                snirf.stim(1,length(snirf.stim)).name=event_name;
            end
            idx_snirfstim = map_stimname(event_name);

            colidx_snirfstim_Onset =  find(strcmp(snirf.stim(1,idx_snirfstim).dataLabels, 'Onset'));
            colidx_snirfstim_Duration =  find(strcmp(snirf.stim(1,idx_snirfstim).dataLabels, 'Duration'));
            colidx_snirfstim_Amplitude =  find(strcmp(snirf.stim(1,idx_snirfstim).dataLabels, 'Amplitude'));
            assert (colidx_snirfstim_Onset==1 && colidx_snirfstim_Duration==2 && colidx_snirfstim_Amplitude==3);  %this is assumed below, so better be true!

            %if caller supplied mapping_events, look for a close match based on time
            found_close_originalevent=false;
            if matchto_original_event
                for idx_mappingevent=1:length(mapping_events)
                    if mapping_events{idx_mappingevent}.EventID_Original == event_id_original
                        arr_mapping = mapping_events{idx_mappingevent}.mapping;
                        %  columns in the mapping array: [event_frame_original event_time_original event_frame_new event_time_new idx_eventtable]
                        for idx_arr_mapping=1:size(arr_mapping,1)
                            if abs(arr_mapping(idx_arr_mapping,2)-tab_events_subject.Onset_sec(idx_tabevents))<=eventime_tolerance_sec
                                found_close_originalevent = true;
                                break;
                            end
                        end   
                    end
                    if found_close_originalevent
                        closest_frame_original = arr_mapping(idx_arr_mapping,1);
                        break; 
                    end
                end
            end
            
            if ~found_close_originalevent
                if allow_unmatched_events
                    %just use the exact time specified in the table, convert to valid file timepoint based on sampling frequency
                    closest_frame_original = round(tab_events_subject.Onset_sec(idx_tabevents)*sampling_frequency)+1;
                else
                    error(['When remapping events for Subject ''%s'', failed to find an existing event within %f seconds of the user-defined event named ''%s'' at %f seconds.\n' ...
                          'Check the original header file to look for the time mark of an event with EventID=%d in section of the recording'], ...
                          tab_events_subject.Subject(idx_tabevents),eventime_tolerance_sec, event_name, ...
                          tab_events_subject.Onset_sec(idx_tabevents), event_id_original);
                end
            end
            if (do_frame_shift)  %if the file was truncated, must change from original index to truncated index values
                if (closest_frame_original<=length(mapping_data)) && (closest_frame_original>0)
                    closest_frame_new = mapping_data(closest_frame_original);
                else
                    closest_frame_new =0;
                end
                if (closest_frame_new==0)  %indicates that this time point was not retained in the truncation process
                    fprintf('For the event at time %d seems to be missing from the truncated data, so is being skipped\n', ...
                            tab_events_subject.Onset_sec(idx_tabevents) );
                    break;
                end
            else
                closest_frame_new = closest_frame_original;
            end
            timepoint = (closest_frame_new-1)/sampling_frequency;

            snirf.stim(1,idx_snirfstim).data = cat(1,snirf.stim(1,idx_snirfstim).data, ...
                         [timepoint tab_events_subject.Duration_sec(idx_tabevents) 1]); 
            snirf.stim(1,idx_snirfstim).states = cat(1,snirf.stim(1,idx_snirfstim).states, ...
                         [timepoint 1]); 
        end
    end

end