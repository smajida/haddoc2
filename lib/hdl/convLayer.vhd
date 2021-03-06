library ieee;
	use	ieee.std_logic_1164.all;
	use	ieee.numeric_std.all;
    use ieee.math_real.all;


library work;
	use work.cnn_types.all;
	use work.bitwidths.all;


entity convLayer is
    generic(
        PIXEL_SIZE    :   integer;
        IMAGE_WIDTH   :   integer;
        KERNEL_SIZE   :   integer;
        NB_IN_FLOWS   :   integer;
        NB_OUT_FLOWS  :   integer;
        KERNEL_VALUE  :   pixel_matrix;
        KERNEL_NORM   :   pixel_array;
        BIAS_VALUE    :   pixel_array
    );

    port(
        clk	          : in  std_logic;
        reset_n	      : in  std_logic;
        enable        : in  std_logic;

        in_data       : in  pixel_array      (0 to NB_IN_FLOWS - 1);
        in_dv         : in  std_logic_vector (0 to NB_IN_FLOWS - 1);
        in_fv         : in  std_logic_vector (0 to NB_IN_FLOWS - 1);

        out_data      : out pixel_array      (0 to NB_OUT_FLOWS - 1);
        out_dv        : out std_logic_vector (0 to NB_OUT_FLOWS - 1);
        out_fv        : out std_logic_vector (0 to NB_OUT_FLOWS - 1)
    );
end entity;

architecture STRUCTURAL of convLayer is

    --------------------------------------------------------------------------------
    -- COMPONENTS
    --------------------------------------------------------------------------------
    component neighExtractor
    generic(
		PIXEL_SIZE      :   integer;
		IMAGE_WIDTH     :   integer;
		KERNEL_SIZE     :   integer
	);

    port(
		clk	            :	in 	std_logic;
        reset_n	        :	in	std_logic;
        enable	        :	in	std_logic;
        in_data         :	in 	std_logic_vector((PIXEL_SIZE-1) downto 0);
        in_dv	        :	in	std_logic;
        in_fv	        :	in	std_logic;
        out_data        :	out	pixel_array (0 to (KERNEL_SIZE * KERNEL_SIZE)- 1);
        out_dv			:	out std_logic;
        out_fv			:	out std_logic
    );
    end component;

    --------------------------------------------------------------------------------
    component convElement
    generic (
      PIXEL_SIZE   : integer;
      KERNEL_SIZE  : integer;
      KERNEL_VALUE : pixel_array
    );
    port (
      clk      : in  std_logic;
      reset_n  : in  std_logic;
      enable   : in  std_logic;
      in_data  : in  pixel_array (0 to KERNEL_SIZE * KERNEL_SIZE - 1);
      in_dv    : in  std_logic;
      in_fv    : in  std_logic;
      out_data : out std_logic_vector(SUM_WIDTH - 1 downto 0);
      out_dv   : out std_logic;
      out_fv   : out std_logic
    );
    end component convElement;
    --------------------------------------------------------------------------------

    component sumElement
    generic(
        PIXEL_SIZE      :   integer;
        NB_IN_FLOWS     :   integer
    );

    port(
        clk	            :	in 	std_logic;
        reset_n	        :	in	std_logic;
        enable          :	in	std_logic;
        in_data         :   in  sum_array        (0 to NB_IN_FLOWS - 1);
        in_dv           :   in  std_logic_vector (0 to NB_IN_FLOWS - 1);
        in_fv           :   in  std_logic_vector (0 to NB_IN_FLOWS - 1);
        in_bias         :   in  std_logic_vector (PIXEL_SIZE - 1 downto 0);
        out_data        :   out std_logic_vector (PIXEL_SIZE - 1 downto 0);
        out_dv          :   out std_logic;
        out_fv          :   out std_logic
    );
    end component;


    --------------------------------------------------------------------------------
    -- SIGNALS
    --------------------------------------------------------------------------------

    type pixel_array_2d is array ( integer range <> ) of pixel_array (0 to KERNEL_SIZE * KERNEL_SIZE - 1);

    -- Output of the neighborhood extractors (in one array of pixel_array)
    signal s_ne_data : pixel_array_2d   (0 to NB_IN_FLOWS -1);
    signal s_ne_dv   : std_logic_vector (0 to NB_IN_FLOWS -1):= (others=>'0');
    signal s_ne_fv   : std_logic_vector (0 to NB_IN_FLOWS -1):= (others=>'0');

    -- Output of the convElements
    signal s_ce_data : sum_array        (0 to NB_IN_FLOWS * NB_OUT_FLOWS -1);
    signal s_ce_dv   : std_logic_vector (0 to NB_IN_FLOWS * NB_OUT_FLOWS -1):= (others=>'0');
    signal s_ce_fv   : std_logic_vector (0 to NB_IN_FLOWS * NB_OUT_FLOWS -1):= (others=>'0');

    -- temporary signal for "easy" indexation purpose
    type   tmp_array_2d is array ( integer range <> ) of sum_array (0 to NB_IN_FLOWS - 1);
    signal ce_data_2d: tmp_array_2d (0 to NB_OUT_FLOWS -1);
        -- Each ce_data_2d(i) will contain NB_IN_FLOWS elements

    signal tmp_w : pixel_array (0 to NB_IN_FLOWS * NB_OUT_FLOWS * KERNEL_SIZE * KERNEL_SIZE - 1):= (others=>(others=>'0'));
    --------------------------------------------------------------------------------
    begin

        NEs_loop : for i in 0 to (NB_IN_FLOWS - 1) generate
            NEs_inst : neighExtractor
            generic map(
                PIXEL_SIZE	 => PIXEL_SIZE,
                IMAGE_WIDTH  => IMAGE_WIDTH,
                KERNEL_SIZE	 => KERNEL_SIZE
            )
            port map(
                clk	         => clk,
                reset_n	     => reset_n,
                enable	     => enable,
                in_data      => in_data(i),
                in_dv	     => in_dv(i),
                in_fv	     => in_fv(i),
                out_data     => s_ne_data(i),
                out_dv	     => s_ne_dv(i),
                out_fv	     => s_ne_fv(i)
            );
        end generate NEs_loop;

    --------------------------------------------------------------------------------

        CEs_loop : for flowIndex in 0 to (NB_OUT_FLOWS * NB_IN_FLOWS - 1) generate


            -- Distrib
            -- Thats a usefull comment :
            -- Dear future me : When I wrote this, only God and I knew what we were doing.
            -- Now, only god knows.
            -- Dear code reader : I apology  for this ...

            --  tmp_loop : for j in 0 to (KERNEL_SIZE * KERNEL_SIZE - 1) generate
            --      tmp_w(i*(KERNEL_SIZE * KERNEL_SIZE) + j) <= KERNEL_VALUE(i,j);
            --  end generate tmp_loop;

            -- Inst Conv Element
            CEs_inst : convElement
            generic map(
                PIXEL_SIZE   => PIXEL_SIZE,
                KERNEL_SIZE  => KERNEL_SIZE,
                KERNEL_VALUE => extractRow(flowIndex,
                                             NB_OUT_FLOWS,
                                             KERNEL_SIZE*KERNEL_SIZE,
                                             KERNEL_VALUE)
            )
            port map(
                clk         => clk,
                reset_n     => reset_n,
                enable      => enable,
                in_data     => s_ne_data (flowIndex/NB_OUT_FLOWS),
                in_dv    	=> s_ne_dv   (flowIndex/NB_OUT_FLOWS),
                in_fv    	=> s_ne_fv   (flowIndex/NB_OUT_FLOWS),
                out_data    => s_ce_data (flowIndex),
                out_dv    	=> s_ce_dv   (flowIndex),
                out_fv    	=> s_ce_fv   (flowIndex)
            );
        end generate CEs_loop;


    --------------------------------------------------------------------------------

      -- Reorganize data : Each ce_data_2d(i) will contain NB_IN_FLOWS elements
      -- Same as line 159
        reorg_i : for i in 0 to (NB_OUT_FLOWS - 1) generate
            reorg_j : for j in 0 to (NB_IN_FLOWS - 1) generate
                --VHDL 2008 only (NOPE !)
                ce_data_2d(i)(j) <= s_ce_data( i + NB_OUT_FLOWS * j);
            end generate reorg_j;
        end generate reorg_i;

        SEs_loop : for i in 0 to (NB_OUT_FLOWS - 1) generate
            SEs_inst : sumElement
            generic map (
                PIXEL_SIZE   => PIXEL_SIZE,
                NB_IN_FLOWS  => NB_IN_FLOWS
            )
            port map(
                clk          => clk,
                reset_n      => reset_n,
                enable       => enable,
                in_data      => ce_data_2d(i),
                in_dv        => s_ce_dv (0 to (NB_IN_FLOWS-1)),
                in_fv        => s_ce_fv (0 to (NB_IN_FLOWS-1)),
                in_bias      => BIAS_VALUE(i),
                out_data     => out_data(i),
                out_dv       => out_dv(i),
                out_fv       => out_fv(i)
            );
        end generate SEs_loop;

    end architecture;
