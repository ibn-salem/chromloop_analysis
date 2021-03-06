#*******************************************************************************
# Analysis different input data types for loop prediction with sevenC. ------
#*******************************************************************************

library(tidyverse)    # for tidy data
library(stringr)      # for string functions
library(precrec)      # for ROC and PRC curves
library(RColorBrewer)   # for nice colors
library(feather)      # for efficient storing of data.frames
library(ROCR)         # for binary clasification metrices

source("R/sevenC.functions.R")

# Set parameter ----------------------------------------------------------------

# use previously saved gi object?
GI_LOCAL <- FALSE
N_CORES = min(10, parallel::detectCores() - 1)

# MIN_MOTIF_SIG <- 5
MOTIF_PVAL <- 2.5 * 1e-06
WINDOW_SIZE <- 1000
BIN_SIZE <- 1
K = 10  # K-fold corss validation
N_TOP_MODELS = 10

outPrefix <- file.path("results", paste0("v06_input_types.", 
                                         paste0("motifPval", MOTIF_PVAL), 
                                         "_w", WINDOW_SIZE, 
                                         "_b", BIN_SIZE))

DATA_TYPES_META_FILE = "data/DATA_TYPES_metadata_v06.tsv"


# Parse and prcessed data and meta data  ---------------------------------------
meta <- read_tsv(paste0(outPrefix, ".meta_filtered.tsv"))

# harmonize data type labels
meta <- meta %>% 
  mutate(
    data_type = data_type %>% 
      str_replace("histone mark ChIP-seq", "ChIP-seq\nhistone mark")
  )

# df <- read_feather(paste0(outPrefix, ".df.feather"))
cvDF <- read_rds(paste0(outPrefix, "cvDF.rds"))
designDF <- read_rds(paste0(outPrefix, "designDF.rds"))

# COL_TF <- brewer.pal(8, "Set2")[c(1:length(unique(meta$TF)), 8)]
# names(COL_TF) <- unique(meta$TF)
COL_TF <- c(brewer.pal(8, "Set2")[1:6], brewer.pal(8, "Accent")[2:6])
names(COL_TF) <- unique(meta$TF)

#pie(rep(1, length(COL_TF)), col = COL_TF, labels = names(COL_TF))

SELECTED_TF <- c(
  "RAD21",
  "CTCF",
  "ZNF143",
  "STAT1",
  "EP300",
  "POLR2A"
)

COL_SELECTED_TF_2 = brewer.pal(12, "Paired")[c(2, 4, 6, 8, 10, 12)]
names(COL_SELECTED_TF_2) <- SELECTED_TF

# define colors for TFs  -------------------------------------------------------
COL_DATA <- c(COL_SELECTED_TF_2, brewer.pal(8, "Accent")[c(2, 1, 4, 6)], "#80B1D3", "#E5C494", "#E78AC3")
names(COL_DATA) <- c(names(COL_SELECTED_TF_2), 
                     "H3K4me1", "H3K4me3", "H3K27me3", "H3K27ac",
                     "SMC3", "input", "DNase-seq")
# plot_col <- function(x){
#   pie(rep(1, length(x)), col = x, labels = names(x))
# }
# plot_col(brewer.pal(8, "Accent")[3:6])
# plot_col(COL_DATA)

#*******************************************************************************
# Performance Evaluation -------------------------------------------------------
#*******************************************************************************

# remove TF_only models
designDF <- designDF %>%
  # filter(!str_detect(name, ".*_only$") ) %>%
  mutate(name = factor(name, name))

# cvDF <- cvDF %>%
#   filter(!str_detect(name, ".*_only$") )

# get AUC of ROC and PRC curves for all 
curves <- evalmod(
  scores = cvDF$pred,
  labels = cvDF$label,
  modnames = as.character(cvDF$name),
  dsids = cvDF$id,
  posclass = levels(cvDF$label[[1]])[2],
  x_bins = 100)

write_rds(curves, paste0(outPrefix, ".curves.rds"))
# curves <- read_rds(paste0(outPrefix, ".curves.rds"))

# get data.frame with auc values
aucDF <-  as_tibble(auc(curves)) %>% 
  mutate(modnames = factor(modnames, designDF$name)) %>% 
  arrange(modnames) %>% 
  mutate(modnames = as.character(modnames))

aucDFmed <- aucDF %>%
  group_by(modnames, curvetypes) %>% 
  summarize(
    aucs_median = median(aucs, na.rm = TRUE),
    aucs_mean = mean(aucs, na.rm = TRUE),
    aucs_sd = sd(aucs, na.rm = TRUE)
  ) %>% 
  ungroup() %>% 
  left_join(meta, by = c("modnames" = "name")) %>% 
  mutate(
    with_sequence_features = grepl("_only$", modnames) %>% 
      ifelse("pure", "with_sequence")
  )

write_feather(aucDFmed, paste0(outPrefix, ".aucDFmed.feather"))
# aucDFmed <- read_feather(paste0(outPrefix, ".aucDFmed.feather"))


# barplot of AUCs by output type -----------------------------------------------
p <- ggplot(aucDFmed, aes(x = modnames, y = aucs_mean, fill = TF)) +
  geom_bar(stat = "identity", position = "dodge", color = "black") +
  geom_errorbar(aes(ymin = aucs_mean - aucs_sd, ymax = aucs_mean + aucs_sd),
                width = .25, position = position_dodge(width = 1)) + 
  geom_text(aes(label = round(aucs_mean, 2), y = aucs_mean - aucs_sd), size = 3, vjust = 1.5) +
  facet_grid(curvetypes ~ with_sequence_features + output_type, scales = "free", space = "free_x") +
  theme_bw() +
  theme(text = element_text(size = 15),
        axis.text.x = element_text(angle = 60, hjust = 1, size = 15),
        legend.position = "right") +
  scale_fill_manual(values = COL_TF) +
  labs(x = "Models", y = "Prediction performance (AUC)")
ggsave(p, file = paste0(outPrefix, ".AUC_ROC_PRC.by_TF.barplot_by_output_type.pdf"), w = 14, h = 10)

# barplot of AUCs by data_type -----------------------------------------------
p <- ggplot(aucDFmed, aes(x = modnames, y = aucs_mean, fill = TF)) +
  geom_bar(stat = "identity", position = "dodge", color = "black") +
  geom_errorbar(aes(ymin = aucs_mean - aucs_sd, ymax = aucs_mean + aucs_sd),
                width = .25, position = position_dodge(width = 1)) + 
  geom_text(aes(label = round(aucs_mean, 2), y = aucs_mean - aucs_sd), size = 3, vjust = 1.5) +
  facet_grid(curvetypes ~ data_type, scales = "free", space = "free_x") +
  theme_bw() +
  theme(text = element_text(size = 15),
        axis.text.x = element_text(angle = 60, hjust = 1, size = 15),
        legend.position = "right") +
  scale_fill_manual(values = COL_TF) +
  labs(x = "Models", y = "Prediction performance (AUC)")
ggsave(p, file = paste0(outPrefix, ".AUC_ROC_PRC.by_TF.barplot_by_data_type.pdf"), w = 14, h = 10)


# Selected plots  --------------------------------------------------------------

meta_sub <- meta %>%
  filter(
    !str_detect(name, ".*_only$"),
    !output_type %in% c("base overlap signal", "raw signal", "signal p-value", "signal_UCSC"),
    !(output_type == "signal" & data_type == "ChIP-seq")
  ) %>% 
  write_tsv(paste0(outPrefix, ".meta_filtered_sub.tsv"))

# get performance of genomic features alone as baseline
genomic_feature_performance <- aucDFmed %>% 
  filter(modnames == "Dist+Orientation+Motif", curvetypes == "PRC") %>% 
  pull(aucs_mean)


subDF <- aucDFmed %>% 
  filter(
    curvetypes == "PRC",
    !str_detect(modnames, ".*_only$"),
    !output_type %in% c("base overlap signal", "raw signal", "signal p-value", "signal_UCSC"),
    # is.na(output_type) | !(output_type == "signal" & data_type == "ChIP-seq")
    !(output_type == "signal" & data_type == "ChIP-seq")
  ) %>% 
  mutate(
    plot_name = ifelse(!is.na(TF), TF, modnames),
    data_type = factor(data_type, c("ChIP-seq", "ChIP-seq\nhistone mark", "DNase-seq", "ChIP-nexus")),
    output_type = factor(output_type, c("fold change over control", "shifted_reads", "qfraq", "input", "signal"))
  )

p <- ggplot(subDF, aes(x = plot_name, y = aucs_mean, fill = TF)) +
  geom_bar(stat = "identity", position = "dodge", color = "black") +
  geom_errorbar(aes(ymin = aucs_mean - aucs_sd, ymax = aucs_mean + aucs_sd),
                width = .25) + 
  geom_text(aes(label = round(aucs_mean, 2), y = aucs_mean - aucs_sd), size = 4, hjust = 1.1) +
  geom_hline(yintercept = genomic_feature_performance, linetype = 2) +
  coord_flip() +
  facet_grid(data_type + output_type ~ . , scales = "free", space = "free_y", switch = NULL) +
  theme_bw() +
  theme(legend.position = "none",
        strip.text.y = element_text(angle = 0)) +
  scale_fill_manual(values = COL_DATA) +
  labs(x = "Input data sets", y = "Prediction performance (auPRC)")
ggsave(p, file = paste0(outPrefix, ".subset.by_TF_and_data_type.barplot.pdf"), w = 6, h = 6)

