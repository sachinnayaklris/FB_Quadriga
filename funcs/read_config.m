% Provide a method of inputing configurations quickly
% config file should be of the format generated by gen_config

fprintf(config_file)
info = jsondecode(fileread(config_file));
sim_style = 1 - info.simulation.CCO_0_MRO_1;
no_rx = numel(info.UE);
batch = 0;

if ~sim_style
    total_time = round(info.simulation.simulation_duration_s);
    random_UEs = info.simulation.random_UEs;
    fs = info.simulation.sampling_frequency_hz;
    max_xy = info.simulation.max_xy;
    if random_UEs == 0
        for i = 1:no_rx
            initial_loc(i, :) = info.UE(i).initial_position;
            velocity = info.UE(i).velocity;
            heading(i) = atan2(velocity(2), velocity(1));
            speed(i) = norm(velocity);
            end_loc(i, :) = initial_loc(i, :) + velocity' * total_time;
            distance(i) = speed(i) * total_time;
        end
        no_rx_min = no_rx;
    else
        P_local = info.simulation.P_local;
        local_radius = info.simulation.local_radius;
        P_turn = info.simulation.P_turn;
        no_rx_min = random_UEs;
        no_rx = random_UEs;
        if isfield(info.simulation, 'ue_seed')
           ue_seed = info.simulation.ue_seed;
        else
            ue_seed = 0;
        end
    end
    ue_seed = info.simulation.ue_seed;
    output_rsrp = info.simulation.output_rsrp == 1;
end

fc = info.simulation.carrier_frequency_Mhz * 1e6;
no_tx = numel(info.BS);
no_sectors = info.BS(1).number_of_sectors;
BW = info.simulation.bandwidth_Mhz;

tx_antenna_3gpp_macro.phi_3dB = info.BS(1).azimuth_beamwidth_degrees;
tx_antenna_3gpp_macro.theta_3dB = info.BS(1).elevation_beamwidth_degrees;
tx_antenna_3gpp_macro.rear_gain = -info.BS(1).front_to_back_ratio;

tx_pwr_dBm = info.BS(1).tx_p_dbm(1);
for i = 1:no_tx
    orientations(no_sectors*(i - 1)+1:i*no_sectors, 1) = info.BS(i).azimuth_rotations_degrees';
    orientations(no_sectors*(i - 1)+1:i*no_sectors, 2) = info.BS(i).downtilts_degrees';
    tx_loc(i, :) = info.BS(i).location';
    Tx_P_dBm(i, :) = info.BS(i).tx_p_dbm;
end
sim_num = info.simulation.sim_num;
scen = info.simulation.scenario;
seed = info.simulation.seed;
if isfield(info.simulation, 'isd')
    if isnumeric(info.simulation.isd)
        isd = info.simulation.isd;
    end
end

rng('default');
rng(seed);

run_i = info.simulation.run_i;

%% Need to add
% reading for antenna models -- '3gpp-macro', 'omni' will be first
sample_distance = info.simulation.sample_distance;

if sim_style
    no_rx_min = info.simulation.no_rx_min;
    n_coords = ceil(sqrt(no_rx_min))^2;
    max_xy = floor((sample_distance*floor(sqrt(n_coords))-1)/2);
    x_min = -max_xy;
end

if strcmp(info.simulation.BS_drop, 'hex') || strcmp(info.simulation.BS_drop, 'rnd') || strcmp(info.simulation.BS_drop, 'csv')
    BS_drop = info.simulation.BS_drop; % should be 'hex', 'rnd', 'csv'
    no_tx = info.simulation.no_tx; % overwrite the tx field

    if numel(info.simulation.batch_tilts) == 0
        error("You need to set the batch_tilts to run BS_drop");
    elseif numel(info.simulation.batch_tilts) == 1
        % overwrite the downtilts with a single value and run once
        fprintf("Setting all downtilts to %i\n", info.simulation.batch_tilts);
        downtilt = info.simulation.batch_tilts;
        orientations = [];
        if sim_style
            sim_style = 1;
        end
    else
        fprintf(['Batch job requested for downtilts =[', num2str(info.simulation.batch_tilts'), ']\n']);
        orientations = [];
        batch = 1;

    end
else
    BS_drop = 0; % If 0, then don't overwrite the placements
    fprintf("Using pre-defined BS\n");
    downtilt = info.simulation.batch_tilts; % TODO need to allow specific downtilt choices
end

if batch == 1 % MRO or CCO multiple tilts
    save_folder_r = [pwd, sprintf('/savedResults/%s/', info.simulation.run_i)];
    
    if ~exist(save_folder_r, 'dir')
        mkdir(save_folder_r);
    end
else
     if ~sim_style % MRO single tilt
        fprintf("Starting MRO with downtilt=%i\n", downtilt);

        save_folder_r = ['savedResults/Scenario ', sim_num, '/'];
        
        if ~exist(save_folder_r, 'dir')
            mkdir(save_folder_r);
        end
        directories = dir(save_folder_r);
        num_dir = numel(directories([directories(:).isdir]))-2;
        save_folder_r = [save_folder_r, 'trial ', num2str(num_dir+1), '/'];
        mkdir(save_folder_r);
     else
         save_folder_r = [pwd, sprintf('/savedResults/%s/', run_i)];
         if ~exist(save_folder_r, 'dir')
            mkdir(save_folder_r);
        end
     end
end


ps = parallel.Settings;
if ~info.simulation.parallel
    ps.Pool.AutoCreate = false;
    poolobj = gcp('nocreate');
    delete(poolobj);
else
    ps.Pool.AutoCreate = true;
    gcp;
end