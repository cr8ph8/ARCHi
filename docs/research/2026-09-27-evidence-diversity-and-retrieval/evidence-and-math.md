# Evidence and mathematical distinctions

27 September 2026. **Reported** means attributed to the linked source, **standard** means a mathematical identity, and **proposed** means an ARCHi design inference. None of the reported numbers below is an ARCHi result.

## 1. Recursive training and evidence retention

**Reported:** Shumailov et al., [Nature, 24 July 2024](https://www.nature.com/articles/s41586-024-07566-y), demonstrate deterioration under recursive generated-data training, including loss of distribution tails. This is not a diagnosis of deployed ChatGPT or ARCHi. In one OPT-125M condition, retaining 10% original data reduced deterioration; that fraction is not a universal safe threshold. The [March 2025 correction](https://www.nature.com/articles/s41586-025-08905-3) changes the theoretical setup to \(\beta_i=\gamma_i=0\), replacing the original reference to \(\alpha_i\).

[Gerstgrasser et al., v2](https://arxiv.org/abs/2404.01413v2) separately report that accumulating original and successive synthetic data avoids collapse in their studied settings, with a bounded-error result for their linear-model analysis. Those conditions do not establish that any real/synthetic mixture is safe.

**Illustrative reconstruction, not either paper's exact equation:** if \(S_t\sim p_{\theta_t}\), replacement uses \(D_{t+1}=S_t\); accumulation retains \(D_0\cup S_0\cup\cdots\cup S_t\). Selection, weighting, sample budget and model error still matter.

**ARCHi implication:** retain source origin and derivation through compression, correction and reuse. Several summaries of one source are one evidence lineage. Human origin is not a truth certificate. Original-source retention must respect explicit forgetting, consent and size limits. The current app's context/method adaptation is distinct from recursive weight training.

## 2. STAIR and the meaning of a valid address

**Reported:** [STAIR v1](https://arxiv.org/html/2609.03874v1) fine-tunes a corpus-specific section retriever using a table of contents. SearchTome covers 18 books across six domains. Table 4 reports Recall@1 of 82.6% versus DSI's 76.9%. Section 6.2 reports non-leaf predictions of 0.05% versus 3.25%; their ratio is 65. This concerns destination validity, not factual-answer errors. Corpus training and synthetic questions limit transfer to changing user documents. The paper's printed leaf notation appears inconsistent with its stated task; use the graph definition below as a corrected restatement, not a verbatim transcription.

**Standard task formulation:**

\[
L_D=\{v\in V_D:\operatorname{outdegree}(v)=0\},\qquad
\hat\ell=\arg\max_{\ell\in L_D}p_\theta(\ell\mid q,\operatorname{ToC}_D).
\]

\[
H_{address}=N^{-1}\sum_i\mathbf1[\hat\ell_i\notin L_{D_i}],\qquad
R@1=N^{-1}\sum_i\mathbf1[\hat\ell_i=\ell_i^*].
\]

**ARCHi implication:** selecting only existing anchors can enforce address validity while still choosing irrelevant text. Source-span integrity, relevance, answer support and abstention require separate observations. Our current lexical selector is not the trained STAIR model. This refresh extends the local 18 September review at `docs/research/2026-09-18-retrieval-replay-evaluation/README.md`; that older package is outside this public source selection.

## 3. A mathematical reference, not another runtime

**Reported:** Tianhua Chen's [195-page primer, v2, 8 September 2026](https://arxiv.org/abs/2605.29713v2) connects PCA/PPCA, autoencoders, VAEs, diffusion, flows, autoregressive models, GANs and energy-based models. It is a derivation reference rather than a new ARCHi architecture.

**Standard VAE identity (chapter 3):**

\[
\mathcal L=\mathbb E_{q_\phi(z\mid x)}[\log p_\theta(x\mid z)]
-D_{KL}(q_\phi(z\mid x)\Vert p(z))\le\log p_\theta(x).
\]

**ARCHi type discipline:** the variational distribution \(q_\phi\) is not Hampton's state vector \(\mathbf q\). A density score \(\nabla_z\log p(z)\) is not a capability score. A learned energy is not automatically the control potential used by `HamptonNumericalDynamics`; neither is an engineering energy-use measurement. A finite bounded step does not establish useful learning or global convergence. Each adapter needs coordinate names, units, basis/model version, uncertainty and its actual runtime consumer.

## 4. Albatross: useful dependencies with incomplete coverage

**Source-limited report:** Sychla, Bongrand and colleagues' preprint is [DOI 10.64898/2026.05.19.726202](https://www.biorxiv.org/content/10.64898/2026.05.19.726202v2). The accessible [author explanation](https://www.rouskinlab.com/articles/albatross/) reports approximately 0.78 median precision and 0.41 recall. The supplied chat attributes 0.80/0.44 and a Type II subclass result to revised material; the v2 full text/PDF was inaccessible, so those revised claims remain unverified here. The [author atlas](https://albatrossrna.org/) lists 75,229 predicted dependency maps, not that many laboratory-resolved structures. The source's interactive illustrations are pedagogical reconstructions.

**Standard measures:**

\[
\operatorname{precision}=\frac{TP}{TP+FP},\qquad
\operatorname{recall}=\frac{TP}{TP+FN}.
\]

Undefined denominators require an explicit reporting policy. Medians of precision and recall cannot be inserted into the F1 formula to claim the study's median F1.

**ARCHi implication:** a sparse dependency graph can contain useful edges while missing important ones. Absence of an inferred edge cannot establish independence or complete correction coverage. Qualified representation readers and relationship memory should retain model/version, input evidence, coverage limits and verification state. This transfers a measurement principle, not RNA-specific code or demonstrated biological understanding into ARCHi.
