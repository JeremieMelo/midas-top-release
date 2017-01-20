package midas
package top

import cde.{Parameters, Config}
import dram_midas._

class ZynqConfigWithMemModel extends Config(new WithLBPipe ++ new ZynqConfig)

class WithLBPipe extends Config(
  (key, _, _) => key match {
    case MemModelKey => Some((p: Parameters) => new MidasMemModel(
      new LatencyPipeConfig(new BaseParams(maxReads = 16, maxWrites = 16)))(p))
  }
)

class DefaultExampleConfig extends Config(new rocketchip.BaseConfig)
class SmallBOOMConfig extends Config(new NoBrPred ++ new boom.SmallBOOMConfig)

class NoBrPred extends Config(
  (key, _, _) => key match {
    case boom.EnableBranchPredictor => false
  }
)
