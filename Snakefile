import os
import pandas as pd

from snakemake.remote.GS import RemoteProvider as GSRemoteProvider
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
from snakemake.remote.FTP import RemoteProvider as FTPRemoteProvider


S3 = GSRemoteProvider()

HTTP = HTTPRemoteProvider()
FTP = FTPRemoteProvider()

BUCKET = 'ec3genomes' 


contigs = [
    # Autosomes
   #'NC_009144_3','NC_009145_3','NC_009146_3','NC_009147_3', #chr1-4
   #'NC_009149_3','NC_009149_3','NC_009150_3','NC_009151_3', #chr5-8
   #'NC_009152_3','NC_009153_3','NC_009154_3','NC_009155_3', #chr9-12
   #'NC_009156_3','NC_009157_3','NC_009158_3','NC_009159_3', #chr13-16
   #'NC_009160_3','NC_009161_3','NC_009162_3','NC_009163_3', #chr17-20
   #'NC_009164_3','NC_009165_3','NC_009166_3','NC_009167_3', #chr21-24
   #'NC_009168_3','NC_009169_3','NC_009170_3','NC_009171_3', #chr25-28
   #'NC_009172_3','NC_009173_3','NC_009174_3',
    'NC_009175_3', #chr29-32    

   #'NC_001640_1',                             # Mitochindria
   #'unplaced'                                 # Unplaced/Chrunk
] 
caller = [
    'gatk',
    'bcftools'
]
maf = [
#   'MAF01',
    'MAF005'
]

fltr = [
    'biallelic',
]

lsts = [
    'MNEc2M', 
#   'MNEc670k', 
#   'SNP70', 
#   'SNP50'
]

vqsr = [
#   '100',
    '995',
#   '99',
]

#singularity: "docker://linkageio/ec3genomes:v0.4.0"

rule all:
    input:
         ancient(S3.remote(expand(f'{BUCKET}/data/vcfs/joint/merged/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz',caller=caller,maf=maf,contig=contigs,fltr=fltr,vqsr=vqsr))),
        # Phased
        #ancient(S3.remote(expand(f'{BUCKET}/data/vcfs/joint/merged/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/phased.vcf.gz',caller=caller,maf=maf,contig=contigs,fltr=fltr,vqsr=vqsr))),

rule phase_VQSRPassed_vcf:
    input:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz'),
        idx = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz.csi'),
    output:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/phased.vcf.gz'),
    params:
        prefix = f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/phased',
        window = 0.05,
        overlap = 0.005,
        mem = '50g'
    resources:
        mem_gb = 50
    threads: 7
    shell:
        '''
            java -Xmx{params.mem} -jar $BEAGLE_JAR \
                gt={input.vcf} \
                out={params.prefix} \
                impute=true \
                nthreads={threads} \
                window={params.window} \
                overlap={params.overlap}
        '''

rule combine_gatk_bcftools_vcfs:
    input:
        gatk_vcf     = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz'),
        gatk_idx     = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz.tbi'),
        bcftools_vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz'),
        bcftools_idx = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz.tbi'),
        fna    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna'),
        fai    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna.fai'),
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.dict')
    output:
        merged_vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/merged/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz')
    shell:
        f''' 
        java -jar $GATK3_JAR \
            -T CombineVariants \
            -R {{input.fna}} \
            --variant:gatk {{input.gatk_vcf}} \
            --variant:bcftools {{input.bcftools_vcf}} \
            -genotypeMergeOptions PRIORITIZE \
            -priority gatk,bcftools
        | bcftools annotate -X ^INFO/set,^FORMAT/GT -O z -o {{output.merged_vcf}}
        ''' 

rule filter_VQSR_passed:
    input:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/ALL.vcf.gz'),
    output:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/PASS.vcf.gz'),
    shell:
        '''
            bcftools view -f PASS {input.vcf} -Ou |\
            bcftools annotate -x ^INFO/VQSLOD,^FORMAT/GT -O z -o {output.vcf}
        '''

rule apply_VQSR_filters_vcf:
    input:
        # VCF 
        vcf    = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz'),
        vcfidx = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz.tbi'),
        # Recalibration input
        recal     = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal'),
        recalidx  = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.idx'),
        plots     = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots'),
        plotspdf  = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots.pdf'),
        tranches  = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches'),
        tranchpdf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches.pdf'),
        # Refgen 
        fna    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna'),
        fai    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna.fai'),
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.dict')
    output:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/VQSR{{vqsr}}/ALL.vcf.gz'),
    run:
        vqsr = int(wildcards.vqsr)
        if vqsr > 100:
            vqsr = vqsr / 10
        else:
            vqsr = vqsr
        shell(f'''
            gatk ApplyVQSR \
            -R {{input.fna}} \
            -V {{input.vcf}} \
            --truth-sensitivity-filter-level {vqsr} \
            --tranches-file {{input.tranches}} \
            --recal-file {{input.recal}} \
            -mode SNP \
            -O {{output.vcf}} 
        ''')

rule recalibrate_bcftoolk_vcf:
    input:
        vcf    = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz'),
        vcfidx = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz.tbi'),
        mnec2m = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/MNEc2M.lst.vcf.gz'),
        index  = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/MNEc2M.lst.vcf.gz.tbi'),
        fna    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna'),
        fai    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna.fai'),
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.dict')
    output:
        recal     = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal'),
        recalidx  = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.idx'),
        plots     = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots'),
        plotspdf  = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots.pdf'),
        tranches  = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches'),
        tranchpdf = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches.pdf'),
    shell:
        '''
            gatk VariantRecalibrator \
            -R {input.fna} \
            -V {input.vcf} \
            --resource:MNEc2M,known=false,training=true,truth=true,prior=15.0 {input.mnec2m} \
            -an DP \
            -an RPB \
            -an MQB \
            -an BQB \
            -an MQSB \
            -an SGB \
            -mode SNP \
            --max-gaussians 4 \
            -tranche 100.0 -tranche 99.9 -tranche 99.5 -tranche 99.0 -tranche 95.0 \
            -O {output.recal} \
            --tranches-file {output.tranches} \
            --rscript-file  {output.plots}
        '''    

rule recalibrate_gatk_vcf:
    input:
        vcf    = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz'),
        vcfidx = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz.tbi'),
        mnec2m = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/MNEc2M.lst.vcf.gz'),
        index  = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/MNEc2M.lst.vcf.gz.tbi'),
        fna    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna'),
        fai    = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna.fai'),
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.dict')
    output:
        recal     = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal'),
        recalidx  = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.idx'),
        plots     = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots'),
        plotspdf  = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.plots.pdf'),
        tranches  = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches'),
        tranchpdf = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/{{fltr}}/{{maf}}/{{contig}}/ALL.recal.tranches.pdf'),
    shell:
        '''
            gatk VariantRecalibrator \
            -R {input.fna} \
            -V {input.vcf} \
            --resource:MNEc2M,known=false,training=true,truth=true,prior=15.0 {input.mnec2m} \
            -an DP \
            -an QD \
            -an MQ \
            -an ReadPosRankSum \
            -an FS \
            -an SOR \
            -mode SNP \
            --max-gaussians 4 \
            -tranche 100.0 -tranche 99.9 -tranche 99.5 -tranche 99.0 -tranche 95.0 \
            -O {output.recal} \
            --tranches-file {output.tranches} \
            --rscript-file  {output.plots}
        '''    

rule subset_ALL_vcf:
    input:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz'),
        idx = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/ALL.vcf.gz.csi'),
        lst = S3.remote(f'{BUCKET}/data/lsts/{{lst}}.lst')
    output: 
        snps=S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/{{lst}}.lst.vcf.gz',keep_local=True)
    shell:
        '''
            bcftools view {input.vcf} -R {input.lst} -o {output.snps} -O z    
        '''

rule index_subset_vcf:
    input:
        vcf   = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/{{lst}}.vcf.gz')
    output:
        index = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/{{lst}}.vcf.gz.tbi',keep_local=True)
    shell:  
        '''
            gatk IndexFeatureFile -I {input.vcf} -O {output.index}
        '''

rule index_vcf:
    input:
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/{{xxx}}.vcf.gz')
    output:
        idx  = S3.remote(f'{BUCKET}/data/vcfs/joint/{{caller}}/{{fltr}}/{{maf}}/{{contig}}/{{xxx}}.vcf.gz.csi',keep_local=True)
    shell:
        '''
            bcftools index {input.vcf} -o {output.idx}
        '''

#-----------------------------------------------------------------------------#
#-                        Create different starting SNP sets                 -#
#-----------------------------------------------------------------------------#

rule filter_joint_bcftools_biallelic:
    input:
        gvcf = S3.remote(f'mccue-lab/ibiodatatransfer2019/joint_bcftools/{{contig}}.gvcf.gz')
    output: 
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/bcftools/biallelic/{{maf}}/{{contig}}/ALL.vcf.gz')
    resources:
        disk_gb = 100,
        mem_gb = 10
    params:
        max_mem =  '10G'
    run:
        if wildcards.maf == 'MAF01':
            min_af = '0.01'
        elif wildcards.maf == 'MAF005':
            min_af = '0.005'
        shell(f'''
            bcftools view -m2 -M2 -v snps,indels --min-af {min_af} {{input.gvcf}} -Ou | \
            bcftools norm -m+any -Ou | \
            bcftools sort -m {{params.max_mem}} -O z -o {{output.vcf}} 
        ''')

rule filter_joint_gatk_biallelic:
    input:
        gvcf = S3.remote(f'mccue-lab/ibiodatatransfer2019/joint_gatk/{{contig}}.gvcf.gz')
    output: 
        vcf = S3.remote(f'{BUCKET}/data/vcfs/joint/gatk/biallelic/{{maf}}/{{contig}}/ALL.vcf.gz')
    resources:
        disk_gb = 500,
        mem_gb = 50
    params:
        max_mem =  '50G'
    run:
        if wildcards.maf == 'MAF01':
            min_af = '0.01'
        elif wildcards.maf == 'MAF005':
            min_af = '0.005'
        shell(f'''
            bcftools view -m2 -M2 -v snps,indels --min-af {min_af} {{input.gvcf}} -Ou | \
            bcftools norm -m+any -Ou | \
            bcftools sort -m {{params.max_mem}} -O z -o {{output.vcf}} 
        ''')


#-----------------------------------------------------------------------------#
#-                           Create Legacy SNP lists                         -#
#-----------------------------------------------------------------------------#

rule make_snp_lsts:
    '''
        good for: LST = [MNEc2M, MNEc670k, SNP70, SNP50]
    '''
    input:
        snps = HTTP.remote('https://www.animalgenome.org/repository/pub/UMN2018.1003/{LST}.unique_remap.FINAL.csv.gz'),
        assembly = FTP.remote('ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/002/863/925/GCF_002863925.1_EquCab3.0/GCF_002863925.1_EquCab3.0_assembly_report.txt')
    output:
        lst = S3.remote(f'{BUCKET}/data/lsts/{{LST}}.lst',keep_local=True)
    run:
        import pandas as pd
        # Read in the assembly mapping
        assembly = pd.read_table(input.assembly ,comment='#', header=None) 
        chrmap =  {x:y for x,y in zip(assembly[0].values, assembly[6].values)}
        # I have NO idea why the HTTP remote returns a list ...
        df = pd.read_table(input.snps[0],sep=',')
        
        def map_chrom(x): 
            'maps the chromosome name in the Beeson et al file to the Ec3 RefSeq file'
            if x in chrmap:
                return chrmap[x]
            elif x.startswith('chrUn_ref'):
                return x.replace('chrUn_ref|','').replace('|','')
            else:
                raise ValueError
        
        # Add the refeseq chromosomes names to each  
        df['CHR'] = [map_chrom(x) for x in df.EC3_chrom]
        df['POS'] = df.EC3_pos
            
        # Output the LSTs file
        df.loc[:,['CHR','POS']].to_csv(output.lst,index=False,header=None,sep='\t')


#-----------------------------------------------------------------------------#
#-                            Move Reference Files                           -#
#-----------------------------------------------------------------------------#

rule move_ref_genome_dict:
    input:
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.fna.dict')
    output:
        fdict  = S3.remote(f'{BUCKET}/data/fna/GCF_002863925.1_EquCab3.0_genomic.dict',keep_local=True)
    shell:
        'cp {input[0]} {output[0]}'

rule move_ref_genome:
    input:
        S3.remote('mccue-lab/ibiodatatransfer2019/GCF_002863925.1_EquCab3.0_genomic/{fna}')
    output:
        S3.remote(f'{BUCKET}/data/fna/{{fna}}',keep_local=True)
    shell:
        'cp {input[0]} {output[0]}'
