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
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with GNAT.String_Split; use GNAT;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.Expect; use GNAT.Expect;

package body OS_Utils is
       
    function Check_Intel_Supported_System (Platform_Name : in String) return Boolean is
    begin
        return Platform_Name = "intel" or else Platform_Name = "amd";
    end;
    
    function Check_SailfishOS_Supported_System (Platform_Name : in String) return Boolean is
    begin
        return Platform_Name = "sailfishos";
    end;

    function Get_GNU_Linux_Name return String is
        F : File_Type; -- File handle
        File_Name : constant String := "/etc/os-release"; -- Filename to read
        Subs : String_Split.Slice_Set; -- Used to slice the read data from stat file
        Seps : constant String := "="; -- Seperator (space) for slicing string
    begin
        Open (F, In_File, File_Name);
        String_Split.Create (S          => Subs, -- Store sliced data in Subs
                             From       => Get_Line (F), -- Read data to slice. We only need the first line of the file
                             Separators => Seps, -- Separator (here space)
                             Mode       => String_Split.Multiple);
        Close (F);
        
        if (String_Split.Slice (Subs, 2) = """Sailfish OS""") then
            return "sailfishos";
        end if;
                
        return "";
    exception
        when others =>
            Put_Line ("Error reading file: " & File_Name);
            OS_Exit (0);
    end;
    
    function Get_Platform_Name return String is
        F_Name : File_Type; -- File handle
        File_Name : constant String := "/proc/cpuinfo"; -- File to read
        Index_Search : Integer; -- Index of platform name in the searched string
        Line_String : Unbounded_String; -- Variable to store each line of the read file
        AMD_vendor : Unbounded_String; -- AMD vendor name
    begin
        Open (F_Name, In_File, File_Name);
        -- Loop through file to check if it's one of the supported ones and get its name
        while not End_Of_File (F_Name) loop
            Line_String := To_Unbounded_String (Get_Line (F_Name));
            
            Index_Search := Index (To_String (Line_String), "GenuineIntel");
            if (Index_Search > 0) then
                return "intel";
            end if;
            
            Index_Search := Index (To_String (Line_String), "AuthenticAMD");
            if (Index_Search > 0) then
                AMD_vendor := To_Unbounded_String ("amd");
            end if;

        end loop;
        
        Close (F_Name);
        
        if (AMD_vendor = "amd") then
            Open (F_Name, In_File, File_Name);
            
            while not End_Of_File (F_Name) loop
                Line_String := To_Unbounded_String (Get_Line (F_Name));
            
                Index_Search := Index (To_String (Line_String), "Ryzen");
                if (Index_Search > 0) then
                    return "amd";
                end if;

            end loop;
            
            Close (F_Name);
        end if;

        return Get_GNU_Linux_Name;
    exception
        when others =>
            Put_Line ("Error reading file: " & File_Name);
            OS_Exit (0);
    end;

end OS_Utils;
