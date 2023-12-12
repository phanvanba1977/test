---------------------------------------------------------------------------------------------------
-- Author:	 		pvba		
-- Company: 		Photron		

-- Date:				2023/10/16
-- Description:	config_fpga_ctrl
--						
-- Version: 		00
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
library work;

entity config_fpga_ctrl is ---config_fpga_ctrl

	port(
		
		clk         				: in  std_logic;
		rst_n         				: in  std_logic;
		--- control signal
		config_start				: in std_logic;
		config_data					: in std_logic_vector (255 downto 0);
		config_valid				: in std_logic;
		config_fpga_sel			: in std_logic_vector(2 downto 0);
		config_done					: out std_logic;
		---
		
		nCONFIG 						: out std_logic;
		nSTATUS 						: in std_logic;
		CONF_DONE 					: in std_logic;
		INIT_DONE 					: in std_logic;	
		CONF_DATA  					: out std_logic_vector(7 downto 0);
		CONF_VALID 					: out std_logic;	---Stratix10 only
		AVST_READY 					: in std_logic; 	---Stratix10 only
		CONF_CLK 					: out std_logic	---Stratix10 case, clock must continuous. In Arria10 case, clock can paulse when not enough data sent.
		
	);
end entity config_fpga_ctrl;

architecture STRUCT of config_fpga_ctrl is
component gpio_ip
port (
		ck      : in  std_logic                    := '0';             --      ck.export
		din     : in  std_logic_vector(1 downto 0) := (others => '0'); --     din.export
		pad_out : out std_logic_vector(0 downto 0)                     -- pad_out.export
		);
end component;


component config_fifo
	port (
		data    : in  std_logic_vector(255 downto 0) := (others => '0'); --  fifo_input.datain
		wrreq   : in  std_logic                      := '0';             --            .wrreq
		rdreq   : in  std_logic                      := '0';             --            .rdreq
		wrclk   : in  std_logic                      := '0';             --            .wrclk
		rdclk   : in  std_logic                      := '0';             --            .rdclk
		aclr    : in  std_logic                      := '0';             --            .aclr
		q       : out std_logic_vector(7 downto 0);                      -- fifo_output.dataout
		wrusedw : out std_logic_vector(7 downto 0);                      --            .wrusedw
		rdempty : out std_logic                                          --            .rdempty
	);
end component;
signal FPGA_TYPE	: std_logic;
constant nconfig_width		: std_logic_vector(5 downto 0):="001111";
 
type config_st_type is (IDLE,n_config_st, wait_nstatus_st, config_fpga_st, wait_init_done_st);
signal config_st				: config_st_type;
signal fpga_ready 			: std_logic;
signal clock_sel 				: std_logic;
signal config_en				: std_logic;
signal fifo_read_en			: std_logic;
signal nconfig_width_cnt 	: std_logic_vector(5 downto 0);
signal fifo_empty				: std_logic;
signal fifo_re					: std_logic;
signal fifo_data				: std_logic_vector(7 downto 0);
signal fifo_wrusedw			: std_logic_vector(7 downto 0);
signal fifo_rst				: std_logic;
signal fifo_we					: std_logic;
signal data						: std_logic_vector(255 downto 0);

begin

process (clk)
begin
	if clk'event and clk ='1' then
		case FPGA_TYPE is
		when '1' => 
			fpga_ready 	<= AVST_READY;
			clock_sel 	<= config_en; 
		when others => 
			fpga_ready 	<= '1';
			clock_sel 	<= fifo_read_en; 
		end case;
	end if;
end process;

process (clk)
begin
	if clk'event and clk ='1' then
		data 		<= config_data;
		fifo_we 	<= config_valid;
	end if;
end process;

config_fifo_i : config_fifo 
port map (
		data    => data,
		wrreq   => fifo_we,
		rdreq   => fifo_re,
		wrclk   => clk,
		rdclk   => clk,
		aclr    => fifo_rst,
		q       => fifo_data, 
		wrusedw => fifo_wrusedw,
		rdempty => fifo_empty
	);

process (clk,rst_n)
begin
	if (rst_n ='0') then
		config_st	<= IDLE;
	elsif clk'event and clk ='1' then
		
		fifo_read_en	<= '0';
		config_en		<= '0';
		fifo_rst			<= '0';
		case config_st is
		when IDLE => 
		
			if config_start ='1' then
				fifo_rst					<= '1';
				config_st				<= n_config_st;
				nconfig_width_cnt 	<= nconfig_width;
			end if;
		
		when n_config_st => 
			
			nCONFIG <= '0';
			
			nconfig_width_cnt <= nconfig_width_cnt -1;
			if (nconfig_width_cnt = 0) then
				config_st	<= wait_nstatus_st;
				nCONFIG 		<= '1';
			end if;
		when wait_nstatus_st => 
			if nSTATUS ='1' then
				config_st	<= config_fpga_st;
			end if;
		
		when config_fpga_st =>
			
			config_en	<= '1';
			
			if (CONF_DONE ='1') then
				config_st	<= wait_init_done_st;
				config_en	<= '0';			
			
			elsif (fifo_empty = '0' and fpga_ready ='1') then
					fifo_read_en <= '1';
			end if;
			
		when wait_init_done_st =>
			if (INIT_DONE ='1') then
				config_st <= IDLE;
			end if;
		end case;
		
	end if;
end process;



gpio_ip_i : gpio_ip
port map
(
		ck      		=> clk,
		din	  		=> '0' & clock_sel,
		pad_out(0) 	=> CONF_CLK
);


fifo_re	<= clock_sel and not fifo_empty;

process (clk)
begin
	if clk'event and clk ='1' then
		CONF_DATA 	<= fifo_data;
		CONF_VALID 	<= fifo_re;
	end if;
end process;


 
end architecture STRUCT;
