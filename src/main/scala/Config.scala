package midas
package top

import dram_midas._

import config.{Parameters, Config}
import tile._
import rocket._
import coreplex._
import uncore.tilelink._
import uncore.coherence._
import uncore.agents._
import uncore.devices.NTiles
import rocketchip._
import testchipip._
import boom._

class ZynqConfigWithMemModel extends Config(new WithMidasTopEndpoints ++ new WithLBPipe ++ new ZynqConfig)
class ZynqConfig extends Config(new WithMidasTopEndpoints ++ new midas.ZynqConfig)
class CatapultConfig extends Config(new WithMidasTopEndpoints ++ new midas.CatapultConfig)

class WithMidasTopEndpoints extends Config(new Config((site, here, up) => {
  case EndpointKey => up(EndpointKey) ++ core.EndpointMap(Seq(
    new endpoints.SimSerialIO,
    new endpoints.SimUART
  ))
}) ++ new WithSerialAdapter)

class WithLBPipe extends Config((site, here ,up) => {
  case MemModelKey => Some((p: Parameters) => new MidasMemModel(
    new LatencyPipeConfig(new BaseParams(maxReads = 16, maxWrites = 16)))(p))
})

class MidasTopConfig extends Config((site, here, up) => {
   case RocketTilesKey => up(RocketTilesKey) map (tile => tile.copy(
     icache = tile.icache map (_.copy(
       nTLBEntries = 32 // TLB reach = 32 * 4KB = 128KB
     )),
     dcache = tile.dcache map (_.copy(
       nTLBEntries = 32 // TLB reach = 32 * 4KB = 128KB
     ))
   ))
 })

class DefaultExampleConfig extends Config(new MidasTopConfig ++
  new WithSerialAdapter ++  new WithNBigCores(1) ++ new rocketchip.BaseConfig)
class DefaultBOOMConfig extends Config(new MidasTopConfig ++ new WithSerialAdapter ++ new boom.BOOMConfig)
class SmallBOOMConfig extends Config(new MidasTopConfig ++ new WithSerialAdapter ++ new boom.SmallBoomConfig)

class RocketChip1GExtMem extends Config(new WithExtMemSize(0x40000000L) ++ new DefaultExampleConfig)
class RocketChip2GExtMem extends Config(new WithExtMemSize(0x80000000L) ++ new DefaultExampleConfig)
class SmallBOOM1GExtMem extends Config(new WithExtMemSize(0x40000000L) ++ new SmallBOOMConfig)
class SmallBOOM2GExtMem extends Config(new WithExtMemSize(0x80000000L) ++ new SmallBOOMConfig)
class DefaultBOOM1GExtMem extends Config(new WithExtMemSize(0x40000000L) ++ new DefaultBOOMConfig)
class DefaultBOOM2GExtMem extends Config(new WithExtMemSize(0x80000000L) ++ new DefaultBOOMConfig)
