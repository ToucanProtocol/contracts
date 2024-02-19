import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const sharedCompilerConfig = {
  optimizer: {
    enabled: true,
    runs: 200,
  }
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.14',
        settings: sharedCompilerConfig,
      },
      {
        version: '0.8.19', // needed by prb-math
        settings: sharedCompilerConfig,
      },
    ],
  },
};

export default config;
