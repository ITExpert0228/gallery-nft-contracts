const BuildingResource = artifacts.require("BuildingResource");
const AccessoryProvider = artifacts.require("AccessoryProvider");
const BuildingResourceProvider = artifacts.require("BuildingResourceProvider");

const setupAccessories = require("../lib/presale/setupAccessories");

module.exports = async (deployer, network, addresses) => {
  // OpenSea proxy registry addresses for rinkeby and mainnet.
  let proxyRegistryAddress = "";
  if (network === 'rinkeby') {
    proxyRegistryAddress = "0xf57b2c51ded3a29e6891aba85459d600256cf317";
  } else {
    proxyRegistryAddress = "0xa5409ec958c83c3f309868babaca7c86dcb077c1";
  }

  let deployAddress = addresses[0];
  let tokenOwner = addresses[0];
  //if (DEPLOY_ACCESSORIES) {
    await deployer.deploy(
      BuildingResource,
      "Building Resource",
      "BRES",
      "",
      proxyRegistryAddress,
      {gas: 5000000, from: deployAddress }
    );
    await deployer.deploy(
      BuildingResourceProvider,
      proxyRegistryAddress,
      BuildingResource.address,
      BuildingResource.address,
      { gas: 5000000, from: deployAddress }
    );
    const accessories = await BuildingResource.deployed();
    const provider = await BuildingResourceProvider.deployed();
    await setupAccessories.setupBuildingAccessories(
      accessories,
      provider,
      tokenOwner
    );
  //}

  // if (DEPLOY_ACCESSORIES_SALE) {
  //   await deployer.deploy(LootBoxRandomness);
  //   await deployer.link(LootBoxRandomness, BuildingAccessoryLootBox);
  //   await deployer.deploy(
  //     BuildingAccessoryLootBox,
  //     proxyRegistryAddress,
  //     { gas: 6721975 }
  //   );
  //   const lootBox = await BuildingAccessoryLootBox.deployed();
  //   await deployer.deploy(
  //     BuildingAccessoryProvider,
  //     proxyRegistryAddress,
  //     BuildingAccessory.address,
  //     BuildingAccessoryLootBox.address,
  //     { gas: 5000000 }
  //   );
  //   const accessories = await BuildingAccessory.deployed();
  //   const provider = await BuildingAccessoryProvider.deployed();
  //   await accessories.transferOwnership(
  //     BuildingAccessoryProvider.address
  //   );
  //   await setupBuildingAccessories.setupAccessoryLootBox(lootBox, provider);
  //   await lootBox.transferOwnership(provider.address);
  // }
};
