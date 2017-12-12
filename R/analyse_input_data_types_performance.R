#*******************************************************************************
# Analysis different input data types for loop prediction with chromloop. ------
#*******************************************************************************

library(tidyverse)    # for tidy data
library(stringr)      # for string functions
library(precrec)      # for ROC and PRC curves
library(RColorBrewer)   # for nice colors
library(feather)      # for efficient storing of data.frames
library(ROCR)         # for binary clasification metrices

source("R/chromloop.functions.R")

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

outPrefix <- file.path("results", paste0("v05_input_types.", 
                                         paste0("motifPval", MOTIF_PVAL), 
                                         "_w", WINDOW_SIZE, 
                                         "_b", BIN_SIZE))

DATA_TYPES_META_FILE = "data/DATA_TYPES_metadata.tsv"


# Parse and prcessed data and meta data  ---------------------------------------
meta <- read_tsv(paste0(outPrefix, ".meta_filtered.tsv"))

COL_TF <- brewer.pal(8, "Set2")[c(1:length(unique(meta$TF)), 8)]
names(COL_TF) <- unique(meta$TF)
#barplot(1:length(COL_TF), col = COL_TF, names.arg = names(COL_TF))

# df <- read_feather(paste0(outPrefix, ".df.feather"))
cvDF <- read_rds(paste0(outPrefix, "cvDF.rds"))
designDF <- read_rds(paste0(outPrefix, "designDF.rds"))

#*******************************************************************************
# Performance Evaluation -------------------------------------------------------
#*******************************************************************************

# remove TF_only models
designDF <- designDF %>%
  filter(!str_detect(name, ".*_only$") ) %>%
  mutate(name = factor(name, name))

cvDF <- cvDF %>%
  filter(!str_detect(name, ".*_only$") )

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
  # add metadata annotation
  mutate(modnames = str_replace(modnames, "Rad21", "RAD21")) %>% 
  left_join(meta, by = c("modnames" = "name"))

# # fix Rad21 into RAD21
# aucDFmed <- aucDFmed
# 
# cvDF <- cvDF %>% 
#   mutate(
#     name = str_replace(name, "Rad21", "RAD21"),
#     meta_name = str_replace(meta_name,  "Rad21", "RAD21")
#   )
# designDF <- designDF %>% 
#   mutate(
#     name = str_replace(name, "Rad21", "RAD21"),
#     meta_name = str_replace(meta_name,  "Rad21", "RAD21")
#   )

write_feather(aucDFmed, paste0(outPrefix, ".aucDFmed.feather"))

# barplot of AUCs by output type -----------------------------------------------
p <- ggplot(aucDFmed, aes(x = modnames, y = aucs_mean, fill = TF)) +
  geom_bar(stat = "identity", position = "dodge", color = "black") +
  geom_errorbar(aes(ymin = aucs_mean - aucs_sd, ymax = aucs_mean + aucs_sd),
                width = .25, position = position_dodge(width = 1)) + 
  geom_text(aes(label = round(aucs_mean, 2), y = aucs_mean - aucs_sd), size = 3, vjust = 1.5) +
  facet_grid(curvetypes ~ output_type, scales = "free", space = "free_x") +
  theme_bw() +
  theme(text = element_text(size = 15),
        axis.text.x = element_text(angle = 60, hjust = 1, size = 15),
        legend.position = "right") +
  scale_fill_manual(values = COL_TF) +
  labs(x = "Models", y = "Prediction performance (AUC)")
ggsave(p, file = paste0(outPrefix, ".AUC_ROC_PRC.by_TF.barplot_by_output_type.pdf"), w = 14, h = 7)

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
ggsave(p, file = paste0(outPrefix, ".AUC_ROC_PRC.by_TF.barplot_by_data_type.pdf"), w = 14, h = 7)


# Selected plots  --------------------------------------------------------------
meta_sub <- meta %>%
  filter(
    !output_type %in% c("base overlap signal", "raw signal", "signal p-value", "signal_UCSC")
  ) %>% 
  write_tsv(paste0(outPrefix, ".meta_filtered_sub.tsv"))

subDF <- aucDFmed %>% 
  filter(
    curvetypes == "PRC",
    !output_type %in% c("base overlap signal", "raw signal", "signal p-value", "signal_UCSC")
    ) %>% 
  mutate(
    plot_name = ifelse(!is.na(TF), TF, modnames)
  )

p <- ggplot(subDF, aes(x = plot_name, y = aucs_mean, fill = TF)) +
  geom_bar(stat = "identity", position = "dodge", color = "black") +
  geom_errorbar(aes(ymin = aucs_mean - aucs_sd, ymax = aucs_mean + aucs_sd),
                width = .25) + 
  geom_text(aes(label = round(aucs_mean, 2), y = aucs_mean - aucs_sd), size = 4, hjust = 1.1) +
  coord_flip() +
  facet_grid(data_type + output_type ~ . , scales = "free", space = "free_y", switch = NULL) +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 60, hjust = 1),
        legend.position = "none",
        strip.text.y = element_text(angle = 0)) +
  scale_fill_manual(values = COL_TF) +
  labs(x = "Models", y = "Prediction performance (auPRC)")
ggsave(p, file = paste0(outPrefix, ".subset.by_TF_and_data_type.barplot.pdf"), w = 6, h = 6)
