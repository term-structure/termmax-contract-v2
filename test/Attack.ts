import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { exec } from "child_process";

describe("Attack", function () {

  async function deployFixture() {
    // Contracts are deployed using the first signer/account by default
    const users = await hre.ethers.getSigners();

    const Weak = await hre.ethers.getContractFactory("Weak");
    const Attacker = await hre.ethers.getContractFactory("Attacker");
    const weak = await Weak.deploy()
    const attacker = await Attacker.deploy(await weak.getAddress())

    await users[0].sendTransaction({
        to: await attacker.getAddress(),
        value: 10000
    })

    return { users, weak, attacker};
  }

  describe("Hack", function () {
    it("Should sucess", async function () {
      const { users, weak, attacker } = await loadFixture(deployFixture);
      const provider = users[0].provider
      await weak.deposit({value: 10000})
      expect(await provider.getBalance(await weak.getAddress())).to.be.eq(10000n)
      await attacker.deposit()
      expect(await provider.getBalance(await weak.getAddress())).to.be.eq(20000n)
      await attacker.hack()
      expect(await provider.getBalance(await attacker.getAddress())).to.be.eq(20000n)
    });

  });

});
