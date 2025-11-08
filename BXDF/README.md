# 一些文件说明
1.Tools目录下的GeneratePreSSLut.shader需要放置在任意一个Resources文件夹中。它与'BSSRDF/Pre-integrationSS/GeneratePreSSLut.cs'彼此依赖，共同生成LUT。如果你对LUT生成流程有新的想法或者改进方案，可以自由修改这两个文件.<br><br>
2.预积分次表面散射的Lut会生成在'Assets/Arts/Textures'目录下，如果没这个目录需要创建一下.<br><br>
3.BRDF中的ReflectionCube是反射纹理，类型为Cubemap.<br><br>
