--
--  Copyright (c) 2020-2021, Adel Noureddine, Université de Pau et des Pays de l'Adour.
--  All rights reserved. This program and the accompanying materials
--  are made available under the terms of the
--  GNU General Public License v3.0 only (GPL-3.0-only)
--  which accompanies this distribution, and is available at:
--  https://www.gnu.org/licenses/gpl-3.0.en.html
--
--  Author : Adel Noureddine
--

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Float_Text_IO; use Ada.Float_Text_IO;
with CPU_Cycles; use CPU_Cycles;
with CSV_Power; use CSV_Power;
with GNAT.Command_Line; use GNAT.Command_Line;
with Help_Info; use Help_Info;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with CPU_STAT_PID; use CPU_STAT_PID;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Intel_RAPL_sysfs; use Intel_RAPL_sysfs;
with OS_Utils; use OS_Utils;
with Nvidia_SMI; use Nvidia_SMI;
with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Ada.Command_Line; use Ada.Command_Line;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with GNAT.Ctrl_C; use GNAT.Ctrl_C;
with Battery_Power; use Battery_Power;

procedure Powerjoular is
    -- Power variables
    --
    -- CPU Power
    CPU_Power : Float; -- Entire CPU power consumption
    Previous_CPU_Power : Float := 0.0; -- Previous CPU power consumption (t - 1)
    PID_CPU_Power : Float; -- CPU power consumption of monitored PID
    Previous_PID_CPU_Power : Float := 0.0; -- Previous CPU power consumption of monitored PID (t - 1)
    CPU_Energy : Float := 0.0;
    --
    -- GPU Power
    GPU_Power : Float := 0.0;
    Previous_GPU_Power : Float := 0.0; -- Previous GPU power consumption (t - 1)
    GPU_Energy : Float := 0.0;
    --
    -- Total Power and Energy
    Previous_Total_Power : Float := 0.0; -- Previous entire total power consumption (t - 1)
    Total_Power : Float := 0.0; -- Total power consumption of all hardware components
    Total_Energy : Float := 0.0; -- Total energy consumed since start of PowerJoular until exit

    -- Data types for Intel RAPL energy monitoring
    RAPL_Before : Intel_RAPL_Data; -- Intel RAPL data
    RAPL_After : Intel_RAPL_Data; -- Intel RAPL data
    RAPL_Energy : Float; -- Intel RAPL energy difference for monitoring cycle

    -- Data types for Nvidia energy monitoring
    Nvidia_Supported : Boolean; -- If nvidia card, drivers and smi tool are available

    -- Data types to monitor CPU cycles
    CPU_CCI_Before : CPU_Cycles_Data; -- Entire CPU cycles
    CPU_CCI_After : CPU_Cycles_Data; -- Entire CPU cycles
    CPU_PID_Before : CPU_STAT_PID_Data; -- Monitored PID CPU cycles
    CPU_PID_After : CPU_STAT_PID_Data; -- Monitored PID CPU cycles

    -- CPU utilization variables
    CPU_Utilization : Float; -- Entire CPU utilization
    PID_CPU_Utilization : Float; -- CPU utilization of monitored PID

    PID_Time : Long_Integer; -- Monitored PID CPU time
    PID_Number : Integer; -- PID number to monitor

    -- Platform name
    Platform_Name : String := Get_Platform_Name;

    -- CSV filenames
    CSV_Filename : Unbounded_String; -- CSV filename for entire CPU power data
    PID_CSV_Filename : Unbounded_String; -- CSV filename for monitored PID CPU power data

    -- Settings
    Show_Terminal : Boolean := False; -- Show power data on terminal
    Print_File: Boolean := False; -- Save power data in file
    Monitor_PID : Boolean := False; -- Monitor a specific PID
    Overwrite_Data : Boolean := false; -- Overwrite data instead of append on file

    -- Procedure to capture Ctrl+C to show total energy on exit
    procedure CtrlCHandler is
    begin
        New_Line;
        Put_Line ("--------------------------");
        Put ("Total energy: ");
        Put (Total_Energy, Exp => 0, Fore => 0, Aft => 2);
        Put_Line (" Joules, including:");
        Put (HT & "CPU energy: ");
        Put (CPU_Energy, Exp => 0, Fore => 0, Aft => 2);
        Put_Line (" Joules");
        Put (HT & "GPU energy: ");
        Put (GPU_Energy, Exp => 0, Fore => 0, Aft => 2);
        Put_Line (" Joules");
        Put_Line ("--------------------------");
        OS_Exit (0);
    end CtrlCHandler;

begin
    -- Capture Ctrl+C and redirect to handler
    Install_Handler(Handler => CtrlCHandler'Unrestricted_Access);

    -- Default CSV filename
    CSV_Filename := To_Unbounded_String ("./powerjoular-power.csv");

    -- Loop over command line options
    loop
        case Getopt ("h t f: p: o: u l") is
        when 'h' => -- Show help
            Show_Help;
            return;
        when 't' => -- Show power data on terminal
            Show_Terminal := True;
        when 'p' => -- Monitor a particular PID
            PID_Number := Integer'Value (Parameter);
            Monitor_PID := True;
        when 'f' => -- Specifiy a filename for CSV file (append data)
            CSV_Filename := To_Unbounded_String (Parameter);
            Print_File := True;
        when 'o' => -- Specifiy a filename for CSV file (overwrite data)
            CSV_Filename := To_Unbounded_String (Parameter);
            Print_File := True;
            Overwrite_Data := True;
        when others =>
            exit;
        end case;
    end loop;

    if (Argument_Count = 0) then
        Show_Terminal := True;
    end if;

    -- If platform not supported, then exit program
    if (Platform_Name = "") then
        Put_Line ("Platform not supported");
        return;
    end if;

    Put_Line ("System info:");
    Put_Line (Ada.Characters.Latin_1.HT & "Platform: " & Platform_Name);

    if Check_Intel_Supported_System (Platform_Name) then
        -- For Intel RAPL, check and populate supported packages first
        Check_Supported_Packages (RAPL_Before, "psys");
        if RAPL_Before.psys_supported then
            Put_Line (Ada.Characters.Latin_1.HT & "Intel RAPL psys: " & Boolean'Image (RAPL_Before.Psys_Supported));
        end if;

        if (not RAPL_Before.psys_supported) then -- Only check for pkg and dram if psys is not supported
            Check_Supported_Packages (RAPL_Before, "pkg");
            Check_Supported_Packages (RAPL_Before, "dram");
            if RAPL_Before.Pkg_Supported then
                Put_Line (Ada.Characters.Latin_1.HT & "Intel RAPL pkg: " & Boolean'Image (RAPL_Before.pkg_supported));
            end if;
            if RAPL_Before.Dram_Supported then
                Put_Line (Ada.Characters.Latin_1.HT & "Intel RAPL dram: " & Boolean'Image (RAPL_Before.Dram_Supported));
            end if;
        end if;
        RAPL_After := RAPL_Before; -- Populate the "after" data type with same checking as the "before" (insteaf of wasting redundant calls to procedure)

        -- Check if Nvidia card is supported
        -- For now, Nvidia support requiers a PC/server, thus Intel support
        Nvidia_Supported := Check_Nvidia_Supported_System;
        if Nvidia_Supported then
            Put_Line (Ada.Characters.Latin_1.HT & "Nvidia supported: " & Boolean'Image (Nvidia_Supported));
        end if;
    end if;

    -- Amend PID CSV file with PID number
    if Monitor_PID then
        PID_CSV_Filename := CSV_Filename & "-" & Trim(Integer'Image (PID_Number), Ada.Strings.Left) & ".csv";
        Put_Line ("Monitoring PID: " & Integer'Image (PID_Number));
    end if;

    -- Main monitoring loop
    loop
        -- Get a first snapshot of current entire CPU cycles
        Calculate_CPU_Cycles (CPU_CCI_Before);
        if Monitor_PID then -- Do the same for CPU cycles of the monitored PID
            Calculate_PID_Time (CPU_PID_Before, PID_Number);
        end if;

        if Check_Intel_Supported_System (Platform_Name) then
            -- Get a first snapshot of Intel RAPL energy data
            Calculate_Energy (RAPL_Before);
        end if;

        -- Wait for 1 second
        delay 1.0;

        -- Get a second snapshot of current entire CPU cycles
        Calculate_CPU_Cycles (CPU_CCI_After);
        if Monitor_PID then -- Do the same for CPU cycles of the monitored PID
            Calculate_PID_Time (CPU_PID_After, PID_Number);
        end if;

        if Check_Intel_Supported_System (Platform_Name) then
            -- Get a first snapshot of Intel RAPL energy data
            Calculate_Energy (RAPL_After);
        end if;

        -- Calculate entire CPU utilization
        CPU_Utilization := (Float (CPU_CCI_After.cbusy) - Float (CPU_CCI_Before.cbusy)) / (Float (CPU_CCI_After.ctotal) - Float (CPU_CCI_Before.ctotal));

        if Check_Intel_Supported_System (Platform_Name) then
            -- Calculate Intel RAPL energy consumption
            RAPL_Energy := RAPL_After.total_energy - RAPL_Before.total_energy;
            CPU_Power := RAPL_Energy;
            Total_Power := CPU_Power;
        end if;

        if Nvidia_Supported then
            -- Calculate GPU power consumption
            GPU_Power := Get_Nvidia_SMI_Power;
            -- Add GPU power to total power
            -- The total power displayed by PowerJoular is therefore : CPU + GPU power
            Total_Power := Total_Power + GPU_Power;
        end if;

        if Check_SailfishOS_Supported_System (Platform_Name) then
            -- Calculate battery power consumption for SailfishOS device
            Total_Power := Get_Battery_Power;
        end if;

        -- If a particular PID is monitored, calculate its CPU time, CPU utilization and CPU power
        if Monitor_PID then
            PID_Time := CPU_PID_After.total_time - CPU_PID_Before.total_time;
            PID_CPU_Utilization := (Float (PID_Time)) / (Float (CPU_CCI_After.ctotal) - Float (CPU_CCI_Before.ctotal));
            PID_CPU_Power := (PID_CPU_Utilization * CPU_Power) / CPU_Utilization;

            -- Show CPU power data on terminal of monitored PID
            if Show_Terminal then
                Show_On_Terminal_PID (PID_CPU_Utilization, PID_CPU_Power, CPU_Utilization, CPU_Power);
            end if;

            -- Save CPU power data to CSV file of monitored PID
            if Print_File then
                Save_PID_To_CSV_File (To_String (PID_CSV_Filename), PID_CPU_Utilization, PID_CPU_Power, Overwrite_Data);
            end if;

            Previous_PID_CPU_Power := PID_CPU_Power;
        end if;

        -- Show total power data on terminal
        if Show_Terminal and (not Monitor_PID) then
            Show_On_Terminal (CPU_Utilization, Total_Power, Previous_Total_Power);
        end if;

        Previous_CPU_Power := CPU_Power;
        Previous_GPU_Power := GPU_Power;
        Previous_Total_Power := Total_Power;

        -- Increment total energy with power of current cycle
        -- Cycle is 1 second, so energy for 1 sec = power
        Total_Energy := Total_Energy + Total_Power;
        CPU_Energy := CPU_Energy + CPU_Power;
        GPU_Energy := GPU_Energy + GPU_Power;

        -- Save total power data to CSV file
        if Print_File then
            Save_To_CSV_File (To_String (CSV_Filename), CPU_Utilization, Total_Power, CPU_Power, GPU_Power, Overwrite_Data);
        end if;
    end loop;
end Powerjoular;
